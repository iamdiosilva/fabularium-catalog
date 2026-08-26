import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_upload_journal.dart';
import 'telegram_client.dart';
import 'telegram_storage_upload_journal_service.dart';

const String telegramRemoteMissingMarker =
    '[REMOTE_MISSING]';

typedef TelegramStorageVerificationProgressCallback =
    void Function(
  TelegramStorageVerificationProgress progress,
);

class TelegramStorageVerificationService {
  TelegramStorageVerificationService._();

  static final TelegramStorageVerificationService instance =
      TelegramStorageVerificationService._();

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  static const int _batchSize =
      100;

  bool isRemoteMissingJournal(
    TelegramStorageUploadJournal? journal,
  ) {
    final error =
        journal?.lastError;

    if (error ==
        null) {
      return false;
    }

    return error
        .trimLeft()
        .startsWith(
          telegramRemoteMissingMarker,
        );
  }

  Future<TelegramStorageVerificationResult>
      verifyAndUpdate({
    required TelegramStorageUploadJournal journal,
    TelegramStorageVerificationProgressCallback?
        onProgress,
  }) async {
    final catalogExpected =
        journal.catalogMessageIds;

    final filesExpected =
        journal.filesMessageIds;

    final structuralErrors =
        <String>[];

    if (journal.fileGroups.isEmpty) {
      structuralErrors.add(
        'no file groups are recorded',
      );
    }

    if (!journal.hasManifest) {
      structuralErrors.add(
        'manifest message ID is missing',
      );
    }

    _report(
      onProgress,
      stage:
          'Checking Telegram messages...',
      checked:
          0,
      total:
          catalogExpected.length +
          filesExpected.length,
    );

    final remote =
        await _verifyRemote(
      catalogChannel:
          journal.catalogChannel,
      catalogMessageIds:
          catalogExpected,
      filesChannel:
          journal.filesChannel,
      filesMessageIds:
          filesExpected,
      onProgress:
          onProgress,
    );

    final missingCatalog =
        catalogExpected
            .where(
              (
                id,
              ) =>
                  !remote
                      .catalogFound
                      .contains(
                        id,
                      ),
            )
            .toList();

    final missingFiles =
        filesExpected
            .where(
              (
                id,
              ) =>
                  !remote
                      .filesFound
                      .contains(
                        id,
                      ),
            )
            .toList();

    final allPresent =
        structuralErrors.isEmpty &&
        missingCatalog.isEmpty &&
        missingFiles.isEmpty;

    if (allPresent) {
      _report(
        onProgress,
        stage:
            'Telegram package verified.',
        checked:
            catalogExpected.length +
            filesExpected.length,
        total:
            catalogExpected.length +
            filesExpected.length,
      );

      return TelegramStorageVerificationResult(
        journal:
            journal,
        allPresent:
            true,
        catalogExpected:
            catalogExpected.length,
        catalogFound:
            remote.catalogFound.length,
        filesExpected:
            filesExpected.length,
        filesFound:
            remote.filesFound.length,
        missingCatalogMessageIds:
            const <int>[],
        missingFilesMessageIds:
            const <int>[],
        structuralErrors:
            const <String>[],
      );
    }

    final error =
        _buildMissingError(
      structuralErrors:
          structuralErrors,
      missingCatalog:
          missingCatalog,
      missingFiles:
          missingFiles,
    );

    /*
     * IMPORTANT:
     *
     * We deliberately keep every recorded
     * message ID in the journal.
     *
     * A partially missing Telegram group must
     * not be resumed blindly because that could
     * duplicate the messages that still exist.
     *
     * Recovery will therefore offer Clean first.
     */
    final updated =
        await _journalService
            .markFailed(
      journal,
      error,
    );

    _report(
      onProgress,
      stage:
          'Telegram package is incomplete.',
      checked:
          catalogExpected.length +
          filesExpected.length,
      total:
          catalogExpected.length +
          filesExpected.length,
    );

    return TelegramStorageVerificationResult(
      journal:
          updated,
      allPresent:
          false,
      catalogExpected:
          catalogExpected.length,
      catalogFound:
          remote.catalogFound.length,
      filesExpected:
          filesExpected.length,
      filesFound:
          remote.filesFound.length,
      missingCatalogMessageIds:
          missingCatalog,
      missingFilesMessageIds:
          missingFiles,
      structuralErrors:
          structuralErrors,
    );
  }

  Future<_TelegramStorageRemoteVerification>
      _verifyRemote({
    required TelegramStorageChannel
        catalogChannel,
    required List<int> catalogMessageIds,
    required TelegramStorageChannel
        filesChannel,
    required List<int> filesMessageIds,
    TelegramStorageVerificationProgressCallback?
        onProgress,
  }) async {
    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<
            _TelegramStorageRemoteVerification>();

    StreamSubscription<dynamic>?
        eventSubscription;

    StreamSubscription<dynamic>?
        errorSubscription;

    StreamSubscription<dynamic>?
        exitSubscription;

    Isolate? isolate;

    final total =
        catalogMessageIds.length +
        filesMessageIds.length;

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
          final checked =
              message['checked'];

          final stage =
              message['stage']
                      ?.toString() ??
                  'Checking Telegram...';

          if (checked is int) {
            _report(
              onProgress,
              stage:
                  stage,
              checked:
                  checked,
              total:
                  total,
            );
          }

          return;
        }

        if (type ==
            'completed') {
          if (completer.isCompleted) {
            return;
          }

          final rawCatalog =
              message['catalogFound'];

          final rawFiles =
              message['filesFound'];

          final catalogFound =
              rawCatalog is List
                  ? rawCatalog
                      .whereType<int>()
                      .toSet()
                  : <int>{};

          final filesFound =
              rawFiles is List
                  ? rawFiles
                      .whereType<int>()
                      .toSet()
                  : <int>{};

          completer.complete(
            _TelegramStorageRemoteVerification(
              catalogFound:
                  catalogFound,
              filesFound:
                  filesFound,
            ),
          );

          return;
        }

        if (type ==
            'error') {
          if (!completer.isCompleted) {
            completer.completeError(
              TelegramStorageVerificationException(
                message['error']
                        ?.toString() ??
                    'Telegram verification failed.',
              ),
            );
          }
        }
      },
    );

    errorSubscription =
        errorPort.listen(
      (
        dynamic rawError,
      ) {
        if (completer.isCompleted) {
          return;
        }

        String message =
            rawError.toString();

        if (rawError is List &&
            rawError.isNotEmpty) {
          message =
              rawError.first.toString();
        }

        completer.completeError(
          TelegramStorageVerificationException(
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
            const TelegramStorageVerificationException(
              'Telegram verification worker stopped unexpectedly.',
            ),
          );
        }
      },
    );

    try {
      isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        _telegramStorageVerificationEntryPoint,
        <String, dynamic>{
          'eventPort':
              eventPort.sendPort,
          'catalogChannelId':
              catalogChannel.id,
          'catalogAccessHash':
              catalogChannel.accessHash,
          'catalogMessageIds':
              catalogMessageIds,
          'filesChannelId':
              filesChannel.id,
          'filesAccessHash':
              filesChannel.accessHash,
          'filesMessageIds':
              filesMessageIds,
          'batchSize':
              _batchSize,
        },
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
        debugName:
            'FabulariumTelegramStorageVerify',
      );

      return await completer.future;
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

  String _buildMissingError({
    required List<String> structuralErrors,
    required List<int> missingCatalog,
    required List<int> missingFiles,
  }) {
    final parts =
        <String>[
      '$telegramRemoteMissingMarker '
          'Telegram verification found an incomplete Storage V3 package.',
    ];

    if (structuralErrors.isNotEmpty) {
      parts.add(
        'Journal: ${structuralErrors.join(', ')}.',
      );
    }

    if (missingCatalog.isNotEmpty) {
      parts.add(
        'Missing Catalog message IDs: '
        '${missingCatalog.join(', ')}.',
      );
    }

    if (missingFiles.isNotEmpty) {
      parts.add(
        'Missing Files message IDs: '
        '${missingFiles.join(', ')}.',
      );
    }

    parts.add(
      'Resume is disabled for this package. '
      'Use Clean to remove the remaining recorded Telegram messages, '
      'then upload the model again.',
    );

    return parts.join(
      ' ',
    );
  }

  void _report(
    TelegramStorageVerificationProgressCallback?
        callback, {
    required String stage,
    required int checked,
    required int total,
  }) {
    callback?.call(
      TelegramStorageVerificationProgress(
        stage:
            stage,
        checkedMessages:
            checked,
        totalMessages:
            total,
      ),
    );
  }
}

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramStorageVerificationEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  final catalogChannelId =
      bootstrap['catalogChannelId'];

  final catalogAccessHash =
      bootstrap['catalogAccessHash'];

  final rawCatalogIds =
      bootstrap['catalogMessageIds'];

  final filesChannelId =
      bootstrap['filesChannelId'];

  final filesAccessHash =
      bootstrap['filesAccessHash'];

  final rawFilesIds =
      bootstrap['filesMessageIds'];

  final batchSize =
      bootstrap['batchSize'];

  if (eventPort is! SendPort ||
      catalogChannelId is! int ||
      catalogAccessHash is! int ||
      rawCatalogIds is! List ||
      filesChannelId is! int ||
      filesAccessHash is! int ||
      rawFilesIds is! List ||
      batchSize is! int ||
      batchSize <=
          0) {
    return;
  }

  final catalogIds =
      rawCatalogIds
          .whereType<int>()
          .where(
            (
              id,
            ) =>
                id >
                0,
          )
          .toSet()
          .toList()
        ..sort();

  final filesIds =
      rawFilesIds
          .whereType<int>()
          .where(
            (
              id,
            ) =>
                id >
                0,
          )
          .toSet()
          .toList()
        ..sort();

  final telegramClient =
      TelegramClient.instance;

  try {
    final client =
        await telegramClient.connect();

    int checked =
        0;

    final catalogFound =
        await _verifyChannelMessages(
      client:
          client,
      channelId:
          catalogChannelId,
      accessHash:
          catalogAccessHash,
      messageIds:
          catalogIds,
      batchSize:
          batchSize,
      onBatch:
          (
        batchCount,
      ) {
        checked +=
            batchCount;

        eventPort.send(
          <String, dynamic>{
            'type':
                'progress',
            'stage':
                'Checking Catalog Channel...',
            'checked':
                checked,
          },
        );
      },
    );

    final filesFound =
        await _verifyChannelMessages(
      client:
          client,
      channelId:
          filesChannelId,
      accessHash:
          filesAccessHash,
      messageIds:
          filesIds,
      batchSize:
          batchSize,
      onBatch:
          (
        batchCount,
      ) {
        checked +=
            batchCount;

        eventPort.send(
          <String, dynamic>{
            'type':
                'progress',
            'stage':
                'Checking Files Channel...',
            'checked':
                checked,
          },
        );
      },
    );

    try {
      await telegramClient.disconnect();
    } catch (_) {}

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'catalogFound':
            catalogFound.toList()
              ..sort(),
        'filesFound':
            filesFound.toList()
              ..sort(),
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    try {
      await telegramClient.disconnect();
    } catch (_) {}

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
  }
}

Future<Set<int>> _verifyChannelMessages({
  required dynamic client,
  required int channelId,
  required int accessHash,
  required List<int> messageIds,
  required int batchSize,
  required void Function(
    int batchCount,
  )
      onBatch,
}) async {
  final found =
      <int>{};

  if (messageIds.isEmpty) {
    return found;
  }

  final channel =
      t.InputChannel(
    channelId:
        channelId,
    accessHash:
        accessHash,
  );

  for (int offset = 0;
      offset <
          messageIds.length;
      offset +=
          batchSize) {
    final end =
        min<int>(
      offset +
          batchSize,
      messageIds.length,
    );

    final batch =
        messageIds.sublist(
      offset,
      end,
    );

    final response =
        await client
            .invoke(
      t.ChannelsGetMessages(
        channel:
            channel,
        id:
            batch
                .map<t.InputMessageBase>(
                  (
                    id,
                  ) =>
                      t.InputMessageID(
                    id:
                        id,
                  ),
                )
                .toList(),
      ),
    )
            .timeout(
      const Duration(
        seconds:
            30,
      ),
    );

    final error =
        response.error;

    if (error !=
        null) {
      throw Exception(
        error.errorMessage,
      );
    }

    final dynamic result =
        response.result;

    if (result ==
        null) {
      throw const TelegramStorageVerificationException(
        'Telegram returned an empty verification response.',
      );
    }

    List<dynamic> messages =
        <dynamic>[];

    try {
      messages =
          List<dynamic>.from(
        result.messages as List,
      );
    } catch (_) {
      throw const TelegramStorageVerificationException(
        'Telegram returned an unsupported message verification response.',
      );
    }

    final requested =
        batch.toSet();

    for (final dynamic message
        in messages) {
      /*
       * Telegram represents a deleted or missing
       * requested message as MessageEmpty.
       */
      if (message is t.MessageEmpty) {
        continue;
      }

      int? id;

      try {
        final dynamic value =
            message;

        id =
            value.id as int?;
      } catch (_) {}

      if (id !=
              null &&
          requested.contains(
            id,
          )) {
        found.add(
          id,
        );
      }
    }

    onBatch(
      batch.length,
    );
  }

  return found;
}

class TelegramStorageVerificationProgress {
  final String stage;

  final int checkedMessages;

  final int totalMessages;

  const TelegramStorageVerificationProgress({
    required this.stage,
    required this.checkedMessages,
    required this.totalMessages,
  });

  double get progress =>
      totalMessages <=
              0
          ? 1
          : (
              checkedMessages /
              totalMessages
            )
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();
}

class TelegramStorageVerificationResult {
  final TelegramStorageUploadJournal journal;

  final bool allPresent;

  final int catalogExpected;

  final int catalogFound;

  final int filesExpected;

  final int filesFound;

  final List<int> missingCatalogMessageIds;

  final List<int> missingFilesMessageIds;

  final List<String> structuralErrors;

  const TelegramStorageVerificationResult({
    required this.journal,
    required this.allPresent,
    required this.catalogExpected,
    required this.catalogFound,
    required this.filesExpected,
    required this.filesFound,
    required this.missingCatalogMessageIds,
    required this.missingFilesMessageIds,
    required this.structuralErrors,
  });

  int get totalExpected =>
      catalogExpected +
      filesExpected;

  int get totalFound =>
      catalogFound +
      filesFound;

  int get totalMissing =>
      missingCatalogMessageIds.length +
      missingFilesMessageIds.length +
      structuralErrors.length;
}

class _TelegramStorageRemoteVerification {
  final Set<int> catalogFound;

  final Set<int> filesFound;

  const _TelegramStorageRemoteVerification({
    required this.catalogFound,
    required this.filesFound,
  });
}

class TelegramStorageVerificationException
    implements Exception {
  final String message;

  const TelegramStorageVerificationException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
