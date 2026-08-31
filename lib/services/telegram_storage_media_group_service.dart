import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:t/t.dart' as t;
import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';
import 'telegram_storage_upload_connection_pool.dart';

enum TelegramStorageMediaKind { photo, document }

class TelegramStorageMediaItem {
  final TelegramStorageMediaKind kind;
  final String filePath, fileName, mimeType, caption, randomIdKey;
  const TelegramStorageMediaItem({required this.kind, required this.filePath, required this.fileName, required this.mimeType, required this.caption, required this.randomIdKey});
}

class TelegramStorageMediaGroupResult {
  final List<int> messageIds;
  final int? groupedId;
  const TelegramStorageMediaGroupResult({required this.messageIds, required this.groupedId});
}

typedef TelegramStorageMediaGroupProgress = void Function(double progress, String stage);

class TelegramStorageMediaGroupService {
  TelegramStorageMediaGroupService._();
  static final TelegramStorageMediaGroupService instance = TelegramStorageMediaGroupService._();
  static const int maxGroupItems = 10;

  Future<TelegramStorageMediaGroupResult> sendGroup({required TelegramStorageChannel channel, required List<TelegramStorageMediaItem> items, TelegramStorageMediaGroupProgress? onProgress}) async {
    if (items.isEmpty) throw const TelegramStorageMediaGroupException('Media group contains no files.');
    if (items.length > maxGroupItems) throw TelegramStorageMediaGroupException('Telegram media groups support at most $maxGroupItems items.');
    final kind = items.first.kind;
    for (final item in items) {
      if (item.kind != kind) throw const TelegramStorageMediaGroupException('Photos and documents cannot be mixed in the same Fabularium media group.');
      if (!await File(item.filePath).exists()) throw TelegramStorageMediaGroupException('File not found: ${item.fileName}');
    }
    final eventPort = ReceivePort(), errorPort = ReceivePort(), exitPort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();
    Isolate? isolate;
    Timer? exitGraceTimer;
    late final StreamSubscription<dynamic> eventSubscription, errorSubscription, exitSubscription;
    eventSubscription = eventPort.listen((dynamic raw) {
      if (raw is! Map) return;
      final message = Map<dynamic,dynamic>.from(raw);
      final type = message['type'];
      if (type == 'progress') {
        final value = message['progress'];
        if (value is num) onProgress?.call(value.toDouble().clamp(0.0,1.0), message['stage']?.toString() ?? 'Uploading...');
      } else if (type == 'completed' && !completer.isCompleted) {
        final result = message['result'];
        completer.complete(result is Map ? Map<String,dynamic>.from(result) : <String,dynamic>{});
      } else if (type == 'error' && !completer.isCompleted) {
        completer.completeError(TelegramStorageMediaGroupException(message['error']?.toString() ?? 'Telegram media group upload failed.'));
      }
    });
    errorSubscription = errorPort.listen((dynamic error) {
      if (completer.isCompleted) return;
      var message = error.toString();
      if (error is List && error.isNotEmpty) message = error.first.toString();
      completer.completeError(TelegramStorageMediaGroupException(message));
    });
    exitSubscription = exitPort.listen((_) {
      if (completer.isCompleted) return;
      exitGraceTimer?.cancel();
      exitGraceTimer = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          completer.completeError(
            const TelegramStorageMediaGroupException(
              'Telegram media group worker stopped unexpectedly.',
            ),
          );
        }
      });
    });
    try {
      isolate = await Isolate.spawn<Map<String,dynamic>>(_telegramStorageMediaGroupEntryPoint, <String,dynamic>{
        'eventPort': eventPort.sendPort, 'channelId': channel.id, 'accessHash': channel.accessHash,
        'items': items.map((item) => <String,dynamic>{
          'kind': item.kind.name, 'filePath': item.filePath, 'fileName': item.fileName, 'mimeType': item.mimeType,
          'caption': item.caption, 'randomId': _stableRandomId(item.randomIdKey),
        }).toList(),
      }, errorsAreFatal: true, onError: errorPort.sendPort, onExit: exitPort.sendPort, debugName: 'FabulariumTelegramMediaGroup');
      final result = await completer.future;
      final rawIds = result['messageIds'];
      final messageIds = rawIds is List ? rawIds.whereType<int>().toList() : <int>[];
      if (messageIds.length != items.length) throw TelegramStorageMediaGroupException('Telegram returned ${messageIds.length} message IDs for ${items.length} files.');
      return TelegramStorageMediaGroupResult(messageIds: messageIds, groupedId: result['groupedId'] is int ? result['groupedId'] as int : null);
    } finally {
      exitGraceTimer?.cancel();
      isolate?.kill(priority: Isolate.immediate);
      await eventSubscription.cancel(); await errorSubscription.cancel(); await exitSubscription.cancel();
      eventPort.close(); errorPort.close(); exitPort.close();
    }
  }

  static int _stableRandomId(String value) {
    const int offset = 1469598103934665603, prime = 1099511628211, mask = 0x7FFFFFFFFFFFFFFF;
    int hash = offset;
    for (final codeUnit in value.codeUnits) { hash ^= codeUnit; hash = (hash * prime) & mask; }
    return hash == 0 ? 1 : hash;
  }
}

@pragma('vm:entry-point')
Future<void> _telegramStorageMediaGroupEntryPoint(Map<String,dynamic> bootstrap) async {
  final eventPort = bootstrap['eventPort'], channelId = bootstrap['channelId'], accessHash = bootstrap['accessHash'], rawItems = bootstrap['items'];
  if (eventPort is! SendPort || channelId is! int || accessHash is! int || rawItems is! List) return;
  final telegramClient = TelegramClient.instance;
  TelegramStorageUploadConnectionPool? uploadPool;
  try {
    var client = await telegramClient.connect();
    final peer = t.InputPeerChannel(channelId: channelId, accessHash: accessHash);
    final items = rawItems.whereType<Map>().map((raw) => Map<String,dynamic>.from(raw)).toList();
    if (items.isEmpty || items.length > 10) throw Exception('Invalid media group size.');
    int totalBytes = 0; bool hasLargeFile = false;
    for (final item in items) {
      final length = await File(item['filePath'] as String).length(); totalBytes += length;
      if (length >= 10 * 1024 * 1024) hasLargeFile = true;
    }
    if (totalBytes <= 0) throw Exception('Media group contains no data.');
    final uploadClients = <dynamic>[client]; int uploadSocketCount = 1;
    if (hasLargeFile) {
      uploadClients..clear()..addAll(List<dynamic>.filled(4, client));
      _sendProgress(eventPort, 0, 'Opening 8 Telegram upload connections...');
      uploadPool = TelegramStorageUploadConnectionPool(telegramClient: telegramClient);
      try {
        await uploadPool.open(size: 8);
        uploadClients..clear()..addAll(uploadPool.clients); uploadSocketCount = uploadPool.size;
        _sendProgress(eventPort, 0, '$uploadSocketCount Telegram upload connections ready.');
      } catch (_) {
        try { await uploadPool.close(); } catch (_) {}
        uploadPool = null;
        _sendProgress(eventPort, 0, 'Upload pool unavailable. Using 4-request fallback.');
      }
    }
    int completedBytes = 0;
    final prepared = <t.InputSingleMedia>[]; final randomIds = <int>[]; final tracker = _TransferRateTracker();
    for (int index=0; index<items.length; index++) {
      final item = items[index];
      final path = item['filePath'] as String, fileName = item['fileName'] as String;
      final mimeType = item['mimeType']?.toString() ?? 'application/octet-stream';
      final caption = item['caption']?.toString() ?? ''; final randomId = item['randomId'] as int; final kind = item['kind']?.toString();
      final file = File(path); final fileSize = await file.length();
      _sendProgress(eventPort, completedBytes / totalBytes * 0.9, 'Preparing ${index+1}/${items.length}: $fileName');
      final inputFile = await _uploadInputFile(
        uploadClients: uploadClients,
        file: file,
        fileName: fileName,
        onBytesUploaded: (uploadedBytes) {
          final totalUploaded = completedBytes + uploadedBytes;
          final rate = tracker.format(totalUploaded);
          final connectionLabel = uploadSocketCount > 1 ? ' • $uploadSocketCount connections' : '';
          _sendProgress(eventPort, totalUploaded / totalBytes * 0.88, 'Uploading ${index+1}/${items.length}: $fileName$connectionLabel${rate == null ? '' : ' • $rate'}');
        },
        onRetry: (partIndex, totalParts, attempt, maxAttempts) {
          _sendProgress(
            eventPort,
            completedBytes / totalBytes * 0.88,
            'Retrying chunk ${partIndex+1}/$totalParts for ${index+1}/${items.length}: $fileName • attempt $attempt/$maxAttempts',
          );
        },
      );
      final isPhoto = kind == TelegramStorageMediaKind.photo.name;
      final t.InputMediaBase uploadedMedia = isPhoto
          ? t.InputMediaUploadedPhoto(
              livePhoto: false,
              spoiler: false,
              file: inputFile,
            )
          : t.InputMediaUploadedDocument(
              nosoundVideo: false,
              forceFile: true,
              spoiler: false,
              file: inputFile,
              mimeType: mimeType,
              attributes: <t.DocumentAttributeBase>[
                t.DocumentAttributeFilename(fileName: fileName),
              ],
            );

      if (isPhoto) {
        // Gallery uploads are small. Keep the existing uploadMedia conversion
        // so albums continue to behave exactly as before.
        _sendProgress(
          eventPort,
          (completedBytes + fileSize) / totalBytes * 0.88,
          'Finalizing ${index+1}/${items.length}: $fileName...',
        );

        final uploadMediaResponse = await client
            .invoke(t.MessagesUploadMedia(peer: peer, media: uploadedMedia))
            .timeout(const Duration(minutes: 5));

        if (uploadMediaResponse.error != null) {
          throw Exception(
            'messages.uploadMedia failed for $fileName: '
            '${uploadMediaResponse.error!.errorMessage}',
          );
        }

        final remoteMedia = _convertUploadedMedia(uploadMediaResponse.result);
        prepared.add(
          t.InputSingleMedia(
            media: remoteMedia,
            randomId: randomId,
            message: caption,
          ),
        );

        completedBytes += fileSize;
        randomIds.add(randomId);

        _sendProgress(
          eventPort,
          completedBytes / totalBytes * 0.9,
          'Finalized ${index+1}/${items.length}: $fileName',
        );
      } else {
        // Large documents can be published directly from
        // InputMediaUploadedDocument. Calling messages.uploadMedia here adds
        // an unnecessary server-side conversion step that was timing out
        // after exactly five minutes for ~1 GB parts.
        prepared.add(
          t.InputSingleMedia(
            media: uploadedMedia,
            randomId: randomId,
            message: caption,
          ),
        );

        completedBytes += fileSize;
        randomIds.add(randomId);

        _sendProgress(
          eventPort,
          completedBytes / totalBytes * 0.9,
          'Uploaded ${index+1}/${items.length}: $fileName • ready to publish',
        );
      }
    }
    final isDocumentGroup =
        items.first['kind']?.toString() == TelegramStorageMediaKind.document.name;

    /*
     * Large uploads can keep the main/control connection idle for many
     * minutes while the 8 auxiliary upload sessions send file chunks.
     *
     * On some networks that idle TCP session becomes half-open. The file
     * chunks are already safely stored by Telegram, but the following
     * messages.sendMedia call then waits forever on the stale control socket.
     *
     * Close the bulk pool first and establish a fresh control connection
     * before publishing the uploaded InputFileBig.
     */
    if (isDocumentGroup) {
      _sendProgress(
        eventPort,
        0.92,
        'Refreshing Telegram control connection...',
      );

      if (uploadPool != null) {
        try {
          await uploadPool.close();
        } catch (_) {}

        uploadPool = null;
      }

      try {
        await telegramClient.disconnect();
      } catch (_) {}

      client = await telegramClient.connect();

      _sendProgress(
        eventPort,
        0.93,
        'Telegram control connection ready.',
      );
    }

    final updates = await _publishPreparedMediaWithRetry(
      telegramClient: telegramClient,
      initialClient: client,
      eventPort: eventPort,
      peer: peer,
      prepared: prepared,
      isDocumentGroup: isDocumentGroup,
    );
    final parsed = _extractSentGroup(updates: updates, randomIds: randomIds);
    _sendProgress(eventPort,1,'Published successfully.');
    eventPort.send(<String,dynamic>{'type':'completed','result':<String,dynamic>{'messageIds':parsed.messageIds,'groupedId':parsed.groupedId}});
  } catch (error, stackTrace) {
    eventPort.send(<String,dynamic>{'type':'error','error':error.toString(),'stackTrace':stackTrace.toString()});
  } finally {
    try { await uploadPool?.close(); } catch (_) {}
    try { await telegramClient.disconnect(); } catch (_) {}
  }
}

typedef _UploadChunkRetryCallback = void Function(
  int partIndex,
  int totalParts,
  int attempt,
  int maxAttempts,
);

Future<t.InputFileBase> _uploadInputFile({
  required List<dynamic> uploadClients,
  required File file,
  required String fileName,
  required void Function(int uploadedBytes) onBytesUploaded,
  required _UploadChunkRetryCallback onRetry,
}) async {
  final size = await file.length();
  if (size <= 0) throw Exception('Cannot upload empty file: $fileName');

  const int partSize = 512 * 1024;
  if (uploadClients.isEmpty) {
    throw Exception('No Telegram upload connections are available.');
  }

  final workerCount = min<int>(8, uploadClients.length);
  final totalParts = (size + partSize - 1) ~/ partSize;
  final isBig = size >= 10 * 1024 * 1024;
  final fileId = _random64();

  int nextPart = 0;
  int uploaded = 0;

  Future<void> runWorker(int workerIndex) async {
    RandomAccessFile? input;
    try {
      input = await file.open(mode: FileMode.read);
      while (true) {
        final partIndex = nextPart;
        if (partIndex >= totalParts) break;
        nextPart++;

        final offset = partIndex * partSize;
        final remaining = size - offset;
        final readLength = min<int>(partSize, remaining);

        await input.setPosition(offset);
        final bytes = await input.read(readLength);

        if (bytes.length != readLength) {
          throw Exception(
            'Unexpected EOF while uploading $fileName at chunk '
            '${partIndex + 1}/$totalParts.',
          );
        }

        await _saveFilePartWithRetry(
          uploadClients: uploadClients,
          preferredClientIndex: workerIndex,
          isBig: isBig,
          fileId: fileId,
          partIndex: partIndex,
          totalParts: totalParts,
          bytes: bytes,
          fileName: fileName,
          onRetry: onRetry,
        );

        uploaded += bytes.length;
        onBytesUploaded(uploaded);
      }
    } finally {
      try {
        await input?.close();
      } catch (_) {}
    }
  }

  await Future.wait(
    List<Future<void>>.generate(workerCount, runWorker),
  );

  if (uploaded != size) {
    throw Exception('Upload byte count mismatch for $fileName: $uploaded/$size.');
  }

  return isBig
      ? t.InputFileBig(id: fileId, parts: totalParts, name: fileName)
      : t.InputFile(
          id: fileId,
          parts: totalParts,
          name: fileName,
          md5Checksum: '',
        );
}

Future<void> _saveFilePartWithRetry({
  required List<dynamic> uploadClients,
  required int preferredClientIndex,
  required bool isBig,
  required int fileId,
  required int partIndex,
  required int totalParts,
  required Uint8List bytes,
  required String fileName,
  required _UploadChunkRetryCallback onRetry,
}) async {
  const int maxAttempts = 3;
  const requestTimeout = Duration(seconds: 90);

  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final clientIndex =
        (preferredClientIndex + attempt - 1) % uploadClients.length;
    final client = uploadClients[clientIndex];

    try {
      final response = isBig
          ? await client
              .invoke(
                t.UploadSaveBigFilePart(
                  fileId: fileId,
                  filePart: partIndex,
                  fileTotalParts: totalParts,
                  bytes: bytes,
                ),
              )
              .timeout(requestTimeout)
          : await client
              .invoke(
                t.UploadSaveFilePart(
                  fileId: fileId,
                  filePart: partIndex,
                  bytes: bytes,
                ),
              )
              .timeout(requestTimeout);

      if (response.error != null) {
        throw Exception(
          'Telegram returned ${response.error!.errorMessage}',
        );
      }

      return;
    } catch (error) {
      lastError = error;

      if (attempt >= maxAttempts) break;

      onRetry(
        partIndex,
        totalParts,
        attempt + 1,
        maxAttempts,
      );

      final backoffSeconds = 1 << (attempt - 1);
      await Future<void>.delayed(
        Duration(seconds: backoffSeconds),
      );
    }
  }

  throw Exception(
    'Upload failed after $maxAttempts attempts on chunk '
    '${partIndex + 1}/$totalParts for $fileName. Last error: $lastError',
  );
}


Future<dynamic> _publishPreparedMediaWithRetry({
  required TelegramClient telegramClient,
  required dynamic initialClient,
  required SendPort eventPort,
  required t.InputPeerBase peer,
  required List<t.InputSingleMedia> prepared,
  required bool isDocumentGroup,
}) async {
  if (prepared.isEmpty) {
    throw Exception('No uploaded media is available for publishing.');
  }

  const maxAttempts = 3;
  const publishTimeout = Duration(minutes: 5);

  dynamic client = initialClient;
  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (attempt > 1) {
      _sendProgress(
        eventPort,
        0.94,
        'Reconnecting before publish retry $attempt/$maxAttempts...',
      );

      try {
        await telegramClient.disconnect();
      } catch (_) {}

      await Future<void>.delayed(
        Duration(seconds: attempt == 2 ? 2 : 5),
      );

      client = await telegramClient.connect();
    }

    _sendProgress(
      eventPort,
      0.95,
      isDocumentGroup
          ? (prepared.length == 1
              ? 'Publishing uploaded file • attempt $attempt/$maxAttempts...'
              : 'Publishing uploaded file group • attempt $attempt/$maxAttempts...')
          : (prepared.length == 1
              ? 'Publishing media...'
              : 'Publishing media group...'),
    );

    try {
      dynamic response;

      if (prepared.length == 1) {
        final item = prepared.first;

        response = await client
            .invoke(
              t.MessagesSendMedia(
                silent: true,
                background: true,
                clearDraft: false,
                noforwards: false,
                updateStickersetsOrder: false,
                invertMedia: false,
                allowPaidFloodskip: false,
                peer: peer,
                media: item.media,
                message: item.message,
                randomId: item.randomId,
              ),
            )
            .timeout(publishTimeout);
      } else {
        response = await client
            .invoke(
              t.MessagesSendMultiMedia(
                silent: true,
                background: true,
                clearDraft: false,
                noforwards: false,
                updateStickersetsOrder: false,
                invertMedia: false,
                allowPaidFloodskip: false,
                peer: peer,
                multiMedia: prepared,
              ),
            )
            .timeout(publishTimeout);
      }

      if (response.error != null) {
        final message = response.error!.errorMessage.toString();

        /*
         * These indicate invalid upload data rather than an unstable control
         * connection, so retrying the same request cannot repair them.
         */
        if (_isNonRetryablePublishError(message)) {
          throw _NonRetryableTelegramPublishException(message);
        }

        throw Exception(message);
      }

      if (response.result == null) {
        throw Exception('Telegram returned an empty publish response.');
      }

      return response.result;
    } on _NonRetryableTelegramPublishException {
      rethrow;
    } catch (error) {
      lastError = error;

      if (!isDocumentGroup || attempt >= maxAttempts) {
        break;
      }

      _sendProgress(
        eventPort,
        0.95,
        'Publish attempt $attempt/$maxAttempts failed. '
        'Refreshing control connection...',
      );
    }
  }

  throw Exception(
    'Telegram could not publish the uploaded file after '
    '$maxAttempts attempts. Last error: $lastError',
  );
}

bool _isNonRetryablePublishError(String message) {
  const markers = <String>[
    'FILE_PARTS_INVALID',
    'FILE_PART_LENGTH_INVALID',
    'INPUT_FILE_INVALID',
    'MEDIA_FILE_INVALID',
    'MEDIA_INVALID',
    'CHAT_WRITE_FORBIDDEN',
    'CHANNEL_PRIVATE',
    'CHANNEL_INVALID',
    'CHAT_ADMIN_REQUIRED',
  ];

  return markers.any(message.contains);
}

class _NonRetryableTelegramPublishException implements Exception {
  final String message;

  const _NonRetryableTelegramPublishException(this.message);

  @override
  String toString() => message;
}

t.InputMediaBase _convertUploadedMedia(dynamic result) {
  if (result == null) throw Exception('Telegram returned empty media.');
  final type = result.runtimeType.toString();
  if (type == 'MessageMediaPhoto') {
    final dynamic photo = result.photo; if (photo == null || photo.runtimeType.toString() != 'Photo') throw Exception('Telegram returned an invalid photo.');
    return t.InputMediaPhoto(livePhoto:false, spoiler:false, id:t.InputPhoto(id:photo.id as int, accessHash:photo.accessHash as int, fileReference:photo.fileReference));
  }
  if (type == 'MessageMediaDocument') {
    final dynamic document = result.document; if (document == null || document.runtimeType.toString() != 'Document') throw Exception('Telegram returned an invalid document.');
    return t.InputMediaDocument(spoiler:false, id:t.InputDocument(id:document.id as int, accessHash:document.accessHash as int, fileReference:document.fileReference));
  }
  throw Exception('Unsupported Telegram media response: $type');
}

_SentMediaGroup _extractSentGroup({required dynamic updates, required List<int> randomIds}) {
  if (updates == null) throw Exception('Telegram returned no updates.');
  if (updates.runtimeType.toString() == 'UpdateShortSentMessage') return _SentMediaGroup(messageIds:<int>[updates.id as int], groupedId:null);
  final mapping = <int,int>{}; final fallback = <int>[]; int? groupedId; List<dynamic> rawUpdates=<dynamic>[];
  try { rawUpdates = List<dynamic>.from(updates.updates as List); } catch (_) {}
  for (final dynamic update in rawUpdates) {
    final type = update.runtimeType.toString();
    if (type == 'UpdateMessageID') { try { mapping[update.randomId as int] = update.id as int; } catch (_) {} continue; }
    if (type == 'UpdateNewChannelMessage' || type == 'UpdateNewMessage') {
      try { final dynamic message=update.message; final id=message.id as int; if(!fallback.contains(id)) fallback.add(id); final dynamic gid=message.groupedId; if(gid is int) groupedId ??= gid; } catch (_) {}
    }
  }
  final ordered=<int>[]; bool complete=true;
  for (final randomId in randomIds) { final id=mapping[randomId]; if(id==null){complete=false;break;} ordered.add(id); }
  if (complete && ordered.length==randomIds.length) return _SentMediaGroup(messageIds:ordered,groupedId:groupedId);
  fallback.sort(); if(fallback.length!=randomIds.length) throw Exception('Could not determine Telegram message IDs for the complete media group.');
  return _SentMediaGroup(messageIds:fallback,groupedId:groupedId);
}

class _SentMediaGroup { final List<int> messageIds; final int? groupedId; const _SentMediaGroup({required this.messageIds, required this.groupedId}); }
int _random64() { final r=Random.secure(); final value=(r.nextInt(1<<31)<<32)|r.nextInt(1<<32); return value==0?1:value; }
class _TransferRateSample { final int microseconds, bytes; const _TransferRateSample({required this.microseconds,required this.bytes}); }
class _TransferRateTracker {
  static const int _windowMicroseconds=2000000; final Stopwatch _watch=Stopwatch()..start(); final List<_TransferRateSample> _samples=[];
  String? format(int totalBytes) {
    final elapsed=_watch.elapsedMicroseconds; if(totalBytes<=0 || elapsed<250000) return null;
    _samples.add(_TransferRateSample(microseconds:elapsed,bytes:totalBytes)); final cutoff=elapsed-_windowMicroseconds;
    while (_samples.length > 2 && _samples[1].microseconds <= cutoff) {
      _samples.removeAt(0);
    }
    final avg=totalBytes/(elapsed/1000000); double current=avg;
    if(_samples.length>=2){final first=_samples.first,last=_samples.last; final dt=last.microseconds-first.microseconds, db=last.bytes-first.bytes; if(dt>0&&db>=0) current=db/(dt/1000000);}
    return 'Current ${_formatTransferRateValue(current)} • Avg ${_formatTransferRateValue(avg)}';
  }
}
String _formatTransferRateValue(double bytesPerSecond) { final safe=max<double>(0,bytesPerSecond); final mbps=safe*8/1000000; if(safe>=1048576)return '${(safe/1048576).toStringAsFixed(2)} MB/s (${mbps.toStringAsFixed(1)} Mbps)'; if(safe>=1024)return '${(safe/1024).toStringAsFixed(0)} KB/s (${mbps.toStringAsFixed(2)} Mbps)'; return '${safe.toStringAsFixed(0)} B/s (${mbps.toStringAsFixed(3)} Mbps)'; }
void _sendProgress(SendPort port,double progress,String stage)=>port.send(<String,dynamic>{'type':'progress','progress':progress.clamp(0.0,1.0).toDouble(),'stage':stage});
class TelegramStorageMediaGroupException implements Exception { final String message; const TelegramStorageMediaGroupException(this.message); @override String toString()=>message; }
