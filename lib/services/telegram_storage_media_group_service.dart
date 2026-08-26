import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';

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

  static const int maxGroupItems = 10;

  // ============================================================
  // SEND GROUP
  // ============================================================

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

    if (items.length > maxGroupItems) {
      throw TelegramStorageMediaGroupException(
        'Telegram media groups support at most '
        '$maxGroupItems items.',
      );
    }

    final kind = items.first.kind;

    for (final item in items) {
      if (item.kind != kind) {
        throw const TelegramStorageMediaGroupException(
          'Photos and documents cannot be mixed '
          'in the same Fabularium media group.',
        );
      }

      final file = File(
        item.filePath,
      );

      if (!await file.exists()) {
        throw TelegramStorageMediaGroupException(
          'File not found: ${item.fileName}',
        );
      }
    }

    final eventPort = ReceivePort();

    final errorPort = ReceivePort();

    final exitPort = ReceivePort();

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

        if (type == 'progress') {
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

        if (type == 'completed') {
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

        if (type == 'error') {
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

    int hash = offset;

    for (final codeUnit
        in value.codeUnits) {
      hash ^= codeUnit;

      hash =
          (hash * prime) &
          mask;
    }

    return hash == 0
        ? 1
        : hash;
  }
}

// ============================================================
// WORKER
// ============================================================

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
        items.length > 10) {
      throw Exception(
        'Invalid media group size.',
      );
    }

    int totalBytes = 0;

    for (final item
        in items) {
      final file =
          File(
        item['filePath']
            as String,
      );

      totalBytes +=
          await file.length();
    }

    if (totalBytes <= 0) {
      throw Exception(
        'Media group contains no data.',
      );
    }

    int completedBytes = 0;

    /*
     * IMPORTANTE:
     *
     * usamos InputSingleMedia concreto,
     * não InputSingleMediaBase.
     *
     * Assim temos acesso a:
     *
     * media
     * message
     * randomId
     */
    final prepared =
        <t.InputSingleMedia>[];

    final randomIds =
        <int>[];

    // ==========================================================
    // PREPARE MEDIA
    // ==========================================================

    for (int index = 0;
        index < items.length;
        index++) {
      final item =
          items[index];

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
        client:
            client,
        file:
            file,
        fileName:
            fileName,
        onBytesUploaded:
            (
          uploadedBytes,
        ) {
          final overall =
              (
                    completedBytes +
                        uploadedBytes
                  ) /
                  totalBytes *
                  0.88;

          _sendProgress(
            eventPort,
            overall,
            'Uploading '
            '${index + 1}/${items.length}: '
            '$fileName',
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

      // ========================================================
      // UPLOAD MEDIA
      // ========================================================

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

      _sendProgress(
        eventPort,
        completedBytes /
            totalBytes *
            0.9,
        'Prepared '
        '${index + 1}/${items.length}.',
      );
    }

    // ==========================================================
    // PUBLISH
    // ==========================================================

    _sendProgress(
      eventPort,
      0.94,
      prepared.length == 1
          ? 'Publishing media...'
          : 'Publishing media group...',
    );

    dynamic updates;

    /*
     * Um único arquivo não gera album.
     *
     * Nesse caso usamos sendMedia.
     */
    if (prepared.length == 1) {
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

      if (response.error != null) {
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

      if (response.error != null) {
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
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

// ============================================================
// RAW FILE UPLOAD
// ============================================================

Future<t.InputFileBase>
    _uploadInputFile({
  required dynamic client,
  required File file,
  required String fileName,
  required void Function(
    int uploadedBytes,
  )
      onBytesUploaded,
}) async {
  final size =
      await file.length();

  if (size <= 0) {
    throw Exception(
      'Cannot upload empty file: '
      '$fileName',
    );
  }

  const int partSize =
      512 * 1024;

  final int totalParts =
      (size +
              partSize -
              1) ~/
          partSize;

  final bool isBig =
      size >=
          10 * 1024 * 1024;

  final fileId =
      _random64();

  RandomAccessFile? input;

  try {
    input =
        await file.open(
      mode:
          FileMode.read,
    );

    int uploaded = 0;

    for (int partIndex = 0;
        partIndex < totalParts;
        partIndex++) {
      final remaining =
          size -
              uploaded;

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

      if (response.error != null) {
        throw Exception(
          'Upload failed on part '
          '${partIndex + 1}/'
          '$totalParts '
          'for $fileName: '
          '${response.error!.errorMessage}',
        );
      }

      uploaded +=
          bytes.length;

      onBytesUploaded(
        uploaded,
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

// ============================================================
// UPLOADED MEDIA -> REMOTE MEDIA
// ============================================================

t.InputMediaBase _convertUploadedMedia(
  dynamic result,
) {
  if (result == null) {
    throw Exception(
      'Telegram returned empty media.',
    );
  }

  final runtimeType =
      result.runtimeType
          .toString();

  // ==========================================================
  // PHOTO
  // ==========================================================

  if (runtimeType ==
      'MessageMediaPhoto') {
    final dynamic photo =
        result.photo;

    if (photo == null ||
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

  // ==========================================================
  // DOCUMENT
  // ==========================================================

  if (runtimeType ==
      'MessageMediaDocument') {
    final dynamic document =
        result.document;

    if (document == null ||
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

// ============================================================
// EXTRACT SENT MESSAGE IDS
// ============================================================

_SentMediaGroup _extractSentGroup({
  required dynamic updates,
  required List<int> randomIds,
}) {
  final randomIdToMessageId =
      <int, int>{};

  final fallbackMessageIds =
      <int>[];

  int? groupedId;

  if (updates == null) {
    throw Exception(
      'Telegram returned no updates.',
    );
  }

  // ==========================================================
  // SINGLE MESSAGE
  // ==========================================================

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

  // ==========================================================
  // UPDATES
  // ==========================================================

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

    /*
     * Esse update associa:
     *
     * randomId -> messageId
     */
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

  // ==========================================================
  // PREFERRED MAPPING
  // ==========================================================

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

    if (id == null) {
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

  // ==========================================================
  // FALLBACK
  // ==========================================================

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

// ============================================================
// HELPERS
// ============================================================

int _random64() {
  final random =
      Random.secure();

  final high =
      random.nextInt(
    1 << 31,
  );

  final low =
      random.nextInt(
    1 << 32,
  );

  final value =
      (high << 32) |
          low;

  return value == 0
      ? 1
      : value;
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