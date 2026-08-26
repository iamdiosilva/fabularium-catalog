import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';
import 'telegram_storage_upload_connection_pool.dart';

enum TelegramStorageMediaKind {
  photo,
  document,
}

class TelegramStorageMediaItem {
  final TelegramStorageMediaKind kind;

  final String filePath;

  final String fileName;

  final String mimeType;

  final String caption;

  final String randomIdKey;

  const TelegramStorageMediaItem({
    required this.kind,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.caption,
    required this.randomIdKey,
  });
}

class TelegramStorageMediaGroupResult {
  final List<int> messageIds;

  final int? groupedId;

  const TelegramStorageMediaGroupResult({
    required this.messageIds,
    required this.groupedId,
  });
}

typedef TelegramStorageMediaGroupProgress =
    void Function(
  double progress,
  String stage,
);

class TelegramStorageMediaGroupService {
  TelegramStorageMediaGroupService._();

  static final TelegramStorageMediaGroupService instance =
      TelegramStorageMediaGroupService._();

  static const int maxGroupItems =
      10;

  Future<TelegramStorageMediaGroupResult>
      sendGroup({
    required TelegramStorageChannel channel,
    required List<TelegramStorageMediaItem> items,
    TelegramStorageMediaGroupProgress?
        onProgress,
  }) async {
    if (items.isEmpty) {
      throw const TelegramStorageMediaGroupException(
        'Media group contains no files.',
      );
    }

    if (items.length >
        maxGroupItems) {
      throw TelegramStorageMediaGroupException(
        'Telegram media groups support at most '
        '$maxGroupItems items.',
      );
    }

    final kind =
        items.first.kind;

    for (final item
        in items) {
      if (item.kind !=
          kind) {
        throw const TelegramStorageMediaGroupException(
          'Photos and documents cannot be mixed '
          'in the same Fabularium media group.',
        );
      }

      final file =
          File(
        item.filePath,
      );

      if (!await file.exists()) {
        throw TelegramStorageMediaGroupException(
          'File not found: ${item.fileName}',
        );
      }
    }

    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<Map<String, dynamic>>();

    Isolate? isolate;

    late final StreamSubscription<dynamic>
        eventSubscription;

    late final StreamSubscription<dynamic>
        errorSubscription;

    late final StreamSubscription<dynamic>
        exitSubscription;

    eventSubscription =
        eventPort.listen(
      (
        dynamic raw,
      ) {
        if (raw is! Map) {
          return;
        }

        final message =
            Map<dynamic, dynamic>.from(
          raw,
        );

        final type =
            message['type'];

        if (type ==
            'progress') {
          final value =
              message['progress'];

          final stage =
              message['stage']
                      ?.toString() ??
                  'Uploading...';

          if (value is num) {
            onProgress?.call(
              value
                  .toDouble()
                  .clamp(
                    0.0,
                    1.0,
                  ),
              stage,
            );
          }

          return;
        }

        if (type ==
            'completed') {
          if (completer.isCompleted) {
            return;
          }

          final result =
              message['result'];

          completer.complete(
            result is Map
                ? Map<String, dynamic>.from(
                    result,
                  )
                : <String, dynamic>{},
          );

          return;
        }

        if (type ==
            'error') {
          if (completer.isCompleted) {
            return;
          }

          completer.completeError(
            TelegramStorageMediaGroupException(
              message['error']
                      ?.toString() ??
                  'Telegram media group upload failed.',
            ),
          );
        }
      },
    );

    errorSubscription =
        errorPort.listen(
      (
        dynamic error,
      ) {
        if (completer.isCompleted) {
          return;
        }

        String message =
            error.toString();

        if (error is List &&
            error.isNotEmpty) {
          message =
              error.first.toString();
        }

        completer.completeError(
          TelegramStorageMediaGroupException(
            message,
          ),
        );
      },
    );

    exitSubscription =
        exitPort.listen(
      (_) {
        if (!completer.isCompleted) {
          completer.completeError(
            const TelegramStorageMediaGroupException(
              'Telegram media group worker '
              'stopped unexpectedly.',
            ),
          );
        }
      },
    );

    try {
      isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        _telegramStorageMediaGroupEntryPoint,
        <String, dynamic>{
          'eventPort':
              eventPort.sendPort,
          'channelId':
              channel.id,
          'accessHash':
              channel.accessHash,
          'items':
              items
                  .map(
                    (
                      item,
                    ) =>
                        <String, dynamic>{
                      'kind':
                          item.kind.name,
                      'filePath':
                          item.filePath,
                      'fileName':
                          item.fileName,
                      'mimeType':
                          item.mimeType,
                      'caption':
                          item.caption,
                      'randomId':
                          _stableRandomId(
                        item.randomIdKey,
                      ),
                    },
                  )
                  .toList(),
        },
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
        debugName:
            'FabulariumTelegramMediaGroup',
      );

      final result =
          await completer.future;

      final rawIds =
          result['messageIds'];

      final messageIds =
          rawIds is List
              ? rawIds
                  .whereType<int>()
                  .toList()
              : <int>[];

      if (messageIds.length !=
          items.length) {
        throw TelegramStorageMediaGroupException(
          'Telegram returned '
          '${messageIds.length} message IDs '
          'for ${items.length} files.',
        );
      }

      final rawGroupedId =
          result['groupedId'];

      return TelegramStorageMediaGroupResult(
        messageIds:
            messageIds,
        groupedId:
            rawGroupedId is int
                ? rawGroupedId
                : null,
      );
    } finally {
      isolate?.kill(
        priority:
            Isolate.immediate,
      );

      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();

      eventPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  static int _stableRandomId(
    String value,
  ) {
    const int offset =
        1469598103934665603;

    const int prime =
        1099511628211;

    const int mask =
        0x7FFFFFFFFFFFFFFF;

    int hash =
        offset;

    for (final codeUnit
        in value.codeUnits) {
      hash ^=
          codeUnit;

      hash =
          (
            hash *
            prime
          ) &
          mask;
    }

    return hash ==
            0
        ? 1
        : hash;
  }
}

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramStorageMediaGroupEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  final channelId =
      bootstrap['channelId'];

  final accessHash =
      bootstrap['accessHash'];

  final rawItems =
      bootstrap['items'];

  if (eventPort is! SendPort ||
      channelId is! int ||
      accessHash is! int ||
      rawItems is! List) {
    return;
  }

  final telegramClient =
      TelegramClient.instance;

  TelegramStorageUploadConnectionPool?
      uploadPool;

  try {
    final client =
        await telegramClient.connect();

    final peer =
        t.InputPeerChannel(
      channelId:
          channelId,
      accessHash:
          accessHash,
    );

    final items =
        rawItems
            .whereType<Map>()
            .map(
              (
                raw,
              ) =>
                  Map<String, dynamic>.from(
                raw,
              ),
            )
            .toList();

    if (items.isEmpty ||
        items.length >
            10) {
      throw Exception(
        'Invalid media group size.',
      );
    }

    int totalBytes =
        0;

    bool hasLargeFile =
        false;

    for (final item
        in items) {
      final file =
          File(
        item['filePath']
            as String,
      );

      final length =
          await file.length();

      totalBytes +=
          length;

      if (length >=
          10 *
              1024 *
              1024) {
        hasLargeFile =
            true;
      }
    }

    if (totalBytes <=
        0) {
      throw Exception(
        'Media group contains no data.',
      );
    }

    final uploadClients =
        <dynamic>[
      client,
    ];

    int uploadSocketCount =
        1;

    /*
     * Arquivos grandes tentam usar oito sessões
     * MTProto independentes.
     *
     * Se o pool não puder ser aberto, mantemos o
     * fallback conservador já validado: quatro requests
     * concorrentes sobre a conexão principal.
     *
     * Assim a Performance V3 nunca transforma um
     * problema do pool em falha do package inteiro.
     */
    if (hasLargeFile) {
      uploadClients
        ..clear()
        ..addAll(
          List<dynamic>.filled(
            4,
            client,
          ),
        );

      _sendProgress(
        eventPort,
        0,
        'Opening 8 Telegram upload connections...',
      );

      uploadPool =
          TelegramStorageUploadConnectionPool(
        telegramClient:
            telegramClient,
      );

      try {
        await uploadPool.open(
          size:
              8,
        );

        uploadClients
          ..clear()
          ..addAll(
            uploadPool.clients,
          );

        uploadSocketCount =
            uploadPool.size;

        _sendProgress(
          eventPort,
          0,
          '$uploadSocketCount Telegram upload connections ready.',
        );
      } catch (_) {
        try {
          await uploadPool?.close();
        } catch (_) {}

        uploadPool =
            null;

        _sendProgress(
          eventPort,
          0,
          '8-socket pool unavailable. Using 4-request fallback.',
        );
      }
    }

    int completedBytes =
        0;

    final prepared =
        <t.InputSingleMedia>[];

    final randomIds =
        <int>[];

    final transferWatch =
        Stopwatch()
          ..start();

    for (int index = 0;
        index <
            items.length;
        index++) {
      final item =
          items[
              index];

      final path =
          item['filePath']
              as String;

      final fileName =
          item['fileName']
              as String;

      final mimeType =
          item['mimeType']
                  ?.toString() ??
              'application/octet-stream';

      final caption =
          item['caption']
                  ?.toString() ??
              '';

      final randomId =
          item['randomId']
              as int;

      final kind =
          item['kind']
              ?.toString();

      final file =
          File(
        path,
      );

      final fileSize =
          await file.length();

      _sendProgress(
        eventPort,
        completedBytes /
            totalBytes *
            0.9,
        'Preparing '
        '${index + 1}/${items.length}: '
        '$fileName',
      );

      final inputFile =
          await _uploadInputFile(
        uploadClients:
            uploadClients,
        file:
            file,
        fileName:
            fileName,
        onBytesUploaded:
            (
          uploadedBytes,
        ) {
          final totalUploaded =
              completedBytes +
              uploadedBytes;

          final overall =
              totalUploaded /
                  totalBytes *
                  0.88;

          final rate =
              _formatTransferRate(
            totalUploaded,
            transferWatch.elapsed,
          );

          final connectionLabel =
              uploadSocketCount >
                      1
                  ? ' • $uploadSocketCount connections'
                  : '';

          _sendProgress(
            eventPort,
            overall,
            'Uploading '
            '${index + 1}/${items.length}: '
            '$fileName'
            '$connectionLabel'
            '${rate == null ? '' : ' • $rate'}',
          );
        },
      );

      final t.InputMediaBase
          uploadedMedia;

      if (kind ==
          TelegramStorageMediaKind
              .photo
              .name) {
        uploadedMedia =
            t.InputMediaUploadedPhoto(
          livePhoto:
              false,
          spoiler:
              false,
          file:
              inputFile,
        );
      } else {
        uploadedMedia =
            t.InputMediaUploadedDocument(
          nosoundVideo:
              false,
          forceFile:
              true,
          spoiler:
              false,
          file:
              inputFile,
          mimeType:
              mimeType,
          attributes:
              <t.DocumentAttributeBase>[
            t.DocumentAttributeFilename(
              fileName:
                  fileName,
            ),
          ],
        );
      }

      final uploadMediaResponse =
          await client
              .invoke(
        t.MessagesUploadMedia(
          peer:
              peer,
          media:
              uploadedMedia,
        ),
      )
              .timeout(
        const Duration(
          seconds:
              90,
        ),
      );

      if (uploadMediaResponse.error !=
          null) {
        throw Exception(
          'messages.uploadMedia failed '
          'for $fileName: '
          '${uploadMediaResponse.error!.errorMessage}',
        );
      }

      final remoteMedia =
          _convertUploadedMedia(
        uploadMediaResponse.result,
      );

      prepared.add(
        t.InputSingleMedia(
          media:
              remoteMedia,
          randomId:
              randomId,
          message:
              caption,
        ),
      );

      randomIds.add(
        randomId,
      );

      completedBytes +=
          fileSize;

      final rate =
          _formatTransferRate(
        completedBytes,
        transferWatch.elapsed,
      );

      _sendProgress(
        eventPort,
        completedBytes /
            totalBytes *
            0.9,
        'Prepared '
        '${index + 1}/${items.length}'
        '${rate == null ? '.' : ' • $rate'}',
      );
    }

    _sendProgress(
      eventPort,
      0.94,
      prepared.length ==
              1
          ? 'Publishing media...'
          : 'Publishing media group...',
    );

    dynamic updates;

    if (prepared.length ==
        1) {
      final item =
          prepared.first;

      final response =
          await client
              .invoke(
        t.MessagesSendMedia(
          silent:
              true,
          background:
              true,
          clearDraft:
              false,
          noforwards:
              false,
          updateStickersetsOrder:
              false,
          invertMedia:
              false,
          allowPaidFloodskip:
              false,
          peer:
              peer,
          media:
              item.media,
          message:
              item.message,
          randomId:
              item.randomId,
        ),
      )
              .timeout(
        const Duration(
          seconds:
              90,
        ),
      );

      if (response.error !=
          null) {
        throw Exception(
          response
              .error!
              .errorMessage,
        );
      }

      updates =
          response.result;
    } else {
      final response =
          await client
              .invoke(
        t.MessagesSendMultiMedia(
          silent:
              true,
          background:
              true,
          clearDraft:
              false,
          noforwards:
              false,
          updateStickersetsOrder:
              false,
          invertMedia:
              false,
          allowPaidFloodskip:
              false,
          peer:
              peer,
          multiMedia:
              prepared,
        ),
      )
              .timeout(
        const Duration(
          seconds:
              90,
        ),
      );

      if (response.error !=
          null) {
        throw Exception(
          response
              .error!
              .errorMessage,
        );
      }

      updates =
          response.result;
    }

    final parsed =
        _extractSentGroup(
      updates:
          updates,
      randomIds:
          randomIds,
    );

    _sendProgress(
      eventPort,
      1,
      'Published successfully.',
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'result':
            <String, dynamic>{
          'messageIds':
              parsed.messageIds,
          'groupedId':
              parsed.groupedId,
        },
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await uploadPool?.close();
    } catch (_) {}

    try {
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

Future<t.InputFileBase>
    _uploadInputFile({
  required List<dynamic> uploadClients,
  required File file,
  required String fileName,
  required void Function(
    int uploadedBytes,
  )
      onBytesUploaded,
}) async {
  final size =
      await file.length();

  if (size <=
      0) {
    throw Exception(
      'Cannot upload empty file: '
      '$fileName',
    );
  }

  /*
   * Telegram recommends 512 KB parts.
   *
   * The important optimization is not a larger
   * part, but keeping multiple save-part RPCs
   * active at the same time.
   */
  const int partSize =
      512 *
      1024;

  if (uploadClients.isEmpty) {
    throw Exception(
      'No Telegram upload connections are available.',
    );
  }

  /*
   * One part per independent MTProto connection.
   *
   * With the V2 pool this normally means:
   *
   *   8 sockets x 512 KB
   *
   * = about 4 MB of file data in flight.
   *
   * Each save-part RPC goes through its own
   * tg.Client/socket whenever the pool is active.
   */
  final int maxConcurrentParts =
      min<int>(
    8,
    uploadClients.length,
  );

  final int totalParts =
      (
            size +
                partSize -
                1
          ) ~/
          partSize;

  final bool isBig =
      size >=
          10 *
              1024 *
              1024;

  final fileId =
      _random64();

  RandomAccessFile? input;

  try {
    input =
        await file.open(
      mode:
          FileMode.read,
    );

    int nextPart =
        0;

    int uploaded =
        0;

    while (nextPart <
        totalParts) {
      final operations =
          <Future<void>>[];

      for (int slot = 0;
          slot <
                  maxConcurrentParts &&
              nextPart <
                  totalParts;
          slot++) {
        final partIndex =
            nextPart;

        nextPart++;

        final expectedOffset =
            partIndex *
            partSize;

        final remaining =
            size -
            expectedOffset;

        final readLength =
            min<int>(
          partSize,
          remaining,
        );

        final bytes =
            await input.read(
          readLength,
        );

        if (bytes.isEmpty) {
          throw Exception(
            'Unexpected EOF while '
            'uploading $fileName.',
          );
        }

        final byteCount =
            bytes.length;

        final uploadClient =
            uploadClients[
              partIndex %
                  uploadClients.length
            ];

        final operation =
            _saveFilePart(
          client:
              uploadClient,
          isBig:
              isBig,
          fileId:
              fileId,
          partIndex:
              partIndex,
          totalParts:
              totalParts,
          bytes:
              bytes,
          fileName:
              fileName,
        ).then(
          (_) {
            uploaded +=
                byteCount;

            onBytesUploaded(
              uploaded,
            );
          },
        );

        operations.add(
          operation,
        );
      }

      await Future.wait(
        operations,
      );
    }

    if (uploaded !=
        size) {
      throw Exception(
        'Upload byte count mismatch for '
        '$fileName: $uploaded/$size.',
      );
    }
  } finally {
    try {
      await input?.close();
    } catch (_) {}
  }

  if (isBig) {
    return t.InputFileBig(
      id:
          fileId,
      parts:
          totalParts,
      name:
          fileName,
    );
  }

  return t.InputFile(
    id:
        fileId,
    parts:
        totalParts,
    name:
        fileName,
    md5Checksum:
        '',
  );
}

Future<void> _saveFilePart({
  required dynamic client,
  required bool isBig,
  required int fileId,
  required int partIndex,
  required int totalParts,
  required Uint8List bytes,
  required String fileName,
}) async {
  final response =
      isBig
          ? await client
              .invoke(
                t.UploadSaveBigFilePart(
                  fileId:
                      fileId,
                  filePart:
                      partIndex,
                  fileTotalParts:
                      totalParts,
                  bytes:
                      bytes,
                ),
              )
              .timeout(
                const Duration(
                  seconds:
                      60,
                ),
              )
          : await client
              .invoke(
                t.UploadSaveFilePart(
                  fileId:
                      fileId,
                  filePart:
                      partIndex,
                  bytes:
                      bytes,
                ),
              )
              .timeout(
                const Duration(
                  seconds:
                      60,
                ),
              );

  if (response.error !=
      null) {
    throw Exception(
      'Upload failed on part '
      '${partIndex + 1}/'
      '$totalParts '
      'for $fileName: '
      '${response.error!.errorMessage}',
    );
  }
}

t.InputMediaBase _convertUploadedMedia(
  dynamic result,
) {
  if (result ==
      null) {
    throw Exception(
      'Telegram returned empty media.',
    );
  }

  final runtimeType =
      result.runtimeType
          .toString();

  if (runtimeType ==
      'MessageMediaPhoto') {
    final dynamic photo =
        result.photo;

    if (photo ==
            null ||
        photo.runtimeType
                .toString() !=
            'Photo') {
      throw Exception(
        'Telegram returned '
        'an invalid photo.',
      );
    }

    return t.InputMediaPhoto(
      livePhoto:
          false,
      spoiler:
          false,
      id:
          t.InputPhoto(
        id:
            photo.id as int,
        accessHash:
            photo.accessHash
                as int,
        fileReference:
            photo.fileReference,
      ),
    );
  }

  if (runtimeType ==
      'MessageMediaDocument') {
    final dynamic document =
        result.document;

    if (document ==
            null ||
        document.runtimeType
                .toString() !=
            'Document') {
      throw Exception(
        'Telegram returned '
        'an invalid document.',
      );
    }

    return t.InputMediaDocument(
      spoiler:
          false,
      id:
          t.InputDocument(
        id:
            document.id as int,
        accessHash:
            document.accessHash
                as int,
        fileReference:
            document.fileReference,
      ),
    );
  }

  throw Exception(
    'Unsupported Telegram media '
    'response: $runtimeType',
  );
}

_SentMediaGroup _extractSentGroup({
  required dynamic updates,
  required List<int> randomIds,
}) {
  final randomIdToMessageId =
      <int, int>{};

  final fallbackMessageIds =
      <int>[];

  int? groupedId;

  if (updates ==
      null) {
    throw Exception(
      'Telegram returned no updates.',
    );
  }

  if (updates.runtimeType
          .toString() ==
      'UpdateShortSentMessage') {
    final dynamic value =
        updates;

    return _SentMediaGroup(
      messageIds:
          <int>[
        value.id as int,
      ],
      groupedId:
          null,
    );
  }

  List<dynamic> rawUpdates =
      <dynamic>[];

  try {
    rawUpdates =
        List<dynamic>.from(
      updates.updates as List,
    );
  } catch (_) {}

  for (final dynamic update
      in rawUpdates) {
    final type =
        update.runtimeType
            .toString();

    if (type ==
        'UpdateMessageID') {
      try {
        randomIdToMessageId[
            update.randomId as int] =
            update.id as int;
      } catch (_) {}

      continue;
    }

    if (type ==
            'UpdateNewChannelMessage' ||
        type ==
            'UpdateNewMessage') {
      try {
        final dynamic message =
            update.message;

        final id =
            message.id as int;

        if (!fallbackMessageIds
            .contains(
          id,
        )) {
          fallbackMessageIds.add(
            id,
          );
        }

        final dynamic rawGroupedId =
            message.groupedId;

        if (rawGroupedId is int) {
          groupedId ??=
              rawGroupedId;
        }
      } catch (_) {}
    }
  }

  final ordered =
      <int>[];

  bool completeMapping =
      true;

  for (final randomId
      in randomIds) {
    final id =
        randomIdToMessageId[
          randomId
        ];

    if (id ==
        null) {
      completeMapping =
          false;

      break;
    }

    ordered.add(
      id,
    );
  }

  if (completeMapping &&
      ordered.length ==
          randomIds.length) {
    return _SentMediaGroup(
      messageIds:
          ordered,
      groupedId:
          groupedId,
    );
  }

  fallbackMessageIds.sort();

  if (fallbackMessageIds.length !=
      randomIds.length) {
    throw Exception(
      'Could not determine Telegram '
      'message IDs for the complete '
      'media group.',
    );
  }

  return _SentMediaGroup(
    messageIds:
        fallbackMessageIds,
    groupedId:
        groupedId,
  );
}

class _SentMediaGroup {
  final List<int> messageIds;

  final int? groupedId;

  const _SentMediaGroup({
    required this.messageIds,
    required this.groupedId,
  });
}

int _random64() {
  final random =
      Random.secure();

  final high =
      random.nextInt(
    1 <<
        31,
  );

  final low =
      random.nextInt(
    1 <<
        32,
  );

  final value =
      (
        high <<
        32
      ) |
      low;

  return value ==
          0
      ? 1
      : value;
}

String? _formatTransferRate(
  int uploadedBytes,
  Duration elapsed,
) {
  final milliseconds =
      elapsed.inMilliseconds;

  if (uploadedBytes <=
          0 ||
      milliseconds <
          250) {
    return null;
  }

  final seconds =
      milliseconds /
      1000;

  final bytesPerSecond =
      uploadedBytes /
      seconds;

  final bitsPerSecond =
      bytesPerSecond *
      8;

  const bytesPerMb =
      1024 *
      1024;

  const bitsPerMbps =
      1000 *
      1000;

  if (bytesPerSecond >=
      bytesPerMb) {
    final megabytesPerSecond =
        bytesPerSecond /
        bytesPerMb;

    final megabitsPerSecond =
        bitsPerSecond /
        bitsPerMbps;

    return '${megabytesPerSecond.toStringAsFixed(2)} MB/s'
        ' • ${megabitsPerSecond.toStringAsFixed(1)} Mbps';
  }

  const bytesPerKb =
      1024;

  if (bytesPerSecond >=
      bytesPerKb) {
    final kilobytesPerSecond =
        bytesPerSecond /
        bytesPerKb;

    final megabitsPerSecond =
        bitsPerSecond /
        bitsPerMbps;

    return '${kilobytesPerSecond.toStringAsFixed(0)} KB/s'
        ' • ${megabitsPerSecond.toStringAsFixed(2)} Mbps';
  }

  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

void _sendProgress(
  SendPort port,
  double progress,
  String stage,
) {
  port.send(
    <String, dynamic>{
      'type':
          'progress',
      'progress':
          progress
              .clamp(
                0.0,
                1.0,
              )
              .toDouble(),
      'stage':
          stage,
    },
  );
}

class TelegramStorageMediaGroupException
    implements Exception {
  final String message;

  const TelegramStorageMediaGroupException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
