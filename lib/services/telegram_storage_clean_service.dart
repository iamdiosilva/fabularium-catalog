import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_upload_journal.dart';
import 'telegram_client.dart';
import 'telegram_storage_upload_journal_service.dart';

typedef TelegramStorageCleanProgressCallback = void Function(
  TelegramStorageCleanProgress progress,
);

class TelegramStorageCleanService {
  TelegramStorageCleanService._();

  static final TelegramStorageCleanService instance =
      TelegramStorageCleanService._();

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  static const int _deleteBatchSize = 100;

  Future<TelegramStorageCleanResult> clean({
    required TelegramStorageUploadJournal journal,
    TelegramStorageCleanProgressCallback? onProgress,
    bool markRemoving = true,
  }) async {
    if (journal.isStored) {
      throw const TelegramStorageCleanException(
        'Stored packages cannot be cleaned by Upload Recovery.',
      );
    }

    var currentJournal = journal;

    if (markRemoving && !currentJournal.isRemoving) {
      currentJournal =
          await _journalService.markRemoving(
        currentJournal,
      );
    }

    final catalogIds =
        currentJournal.catalogMessageIds;

    final filesIds =
        currentJournal.filesMessageIds;

    final totalMessages =
        catalogIds.length + filesIds.length;

    int deletedMessages = 0;

    _report(
      onProgress,
      stage: 'Cleaning Telegram messages...',
      deletedMessages: deletedMessages,
      totalMessages: totalMessages,
    );

    if (catalogIds.isNotEmpty) {
      await _deleteMessages(
        channel: currentJournal.catalogChannel,
        messageIds: catalogIds,
        onDeleted: (count) {
          deletedMessages = count;

          _report(
            onProgress,
            stage: 'Cleaning Catalog Channel...',
            deletedMessages: deletedMessages,
            totalMessages: totalMessages,
          );
        },
      );
    }

    if (filesIds.isNotEmpty) {
      final catalogDeleted =
          deletedMessages;

      await _deleteMessages(
        channel: currentJournal.filesChannel,
        messageIds: filesIds,
        onDeleted: (count) {
          deletedMessages =
              catalogDeleted + count;

          _report(
            onProgress,
            stage: 'Cleaning Files Channel...',
            deletedMessages: deletedMessages,
            totalMessages: totalMessages,
          );
        },
      );
    }

    _report(
      onProgress,
      stage: 'Removing local staging files...',
      deletedMessages: deletedMessages,
      totalMessages: totalMessages,
    );

    final staging =
        Directory(
      currentJournal.stagingDirectoryPath,
    );

    if (await staging.exists()) {
      try {
        await staging.delete(
          recursive: true,
        );
      } catch (error) {
        throw TelegramStorageCleanException(
          'Telegram messages were removed, but the local staging '
          'folder could not be deleted: $error',
        );
      }
    }

    _report(
      onProgress,
      stage: 'Removing local upload journal...',
      deletedMessages: deletedMessages,
      totalMessages: totalMessages,
    );

    try {
      await _journalService.delete(
        currentJournal.packageId,
      );
    } catch (error) {
      throw TelegramStorageCleanException(
        'Telegram messages and staging files were removed, but the '
        'local journal could not be deleted: $error',
      );
    }

    _report(
      onProgress,
      stage: 'Clean completed.',
      deletedMessages: deletedMessages,
      totalMessages: totalMessages,
    );

    return TelegramStorageCleanResult(
      packageId: currentJournal.packageId,
      catalogMessagesDeleted: catalogIds.length,
      filesMessagesDeleted: filesIds.length,
      stagingRemoved: true,
      journalRemoved: true,
    );
  }

  Future<void> _deleteMessages({
    required TelegramStorageChannel channel,
    required List<int> messageIds,
    required void Function(int deletedCount) onDeleted,
  }) async {
    final ids = messageIds
        .where((id) => id > 0)
        .toSet()
        .toList()
      ..sort();

    if (ids.isEmpty) {
      onDeleted(0);
      return;
    }

    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<void>();

    StreamSubscription<dynamic>? eventSubscription;
    StreamSubscription<dynamic>? errorSubscription;
    StreamSubscription<dynamic>? exitSubscription;

    Isolate? isolate;

    eventSubscription =
        eventPort.listen(
      (dynamic raw) {
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
          final deleted =
              message['deleted'];

          if (deleted is int) {
            onDeleted(
              min(
                max(
                  deleted,
                  0,
                ),
                ids.length,
              ),
            );
          }

          return;
        }

        if (type == 'completed') {
          if (!completer.isCompleted) {
            onDeleted(
              ids.length,
            );
            completer.complete();
          }

          return;
        }

        if (type == 'error') {
          if (!completer.isCompleted) {
            completer.completeError(
              TelegramStorageCleanException(
                message['error']
                        ?.toString() ??
                    'Telegram clean failed.',
              ),
            );
          }
        }
      },
    );

    errorSubscription =
        errorPort.listen(
      (dynamic rawError) {
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
          TelegramStorageCleanException(
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
            const TelegramStorageCleanException(
              'Telegram clean worker stopped unexpectedly.',
            ),
          );
        }
      },
    );

    try {
      isolate =
          await Isolate.spawn<Map<String, dynamic>>(
        _telegramStorageCleanMessagesEntryPoint,
        <String, dynamic>{
          'eventPort': eventPort.sendPort,
          'channelId': channel.id,
          'accessHash': channel.accessHash,
          'messageIds': ids,
          'batchSize': _deleteBatchSize,
        },
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'FabulariumTelegramStorageClean',
      );

      await completer.future;
    } finally {
      isolate?.kill(
        priority: Isolate.immediate,
      );

      await eventSubscription?.cancel();
      await errorSubscription?.cancel();
      await exitSubscription?.cancel();

      eventPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  void _report(
    TelegramStorageCleanProgressCallback? callback, {
    required String stage,
    required int deletedMessages,
    required int totalMessages,
  }) {
    callback?.call(
      TelegramStorageCleanProgress(
        stage: stage,
        deletedMessages: deletedMessages,
        totalMessages: totalMessages,
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> _telegramStorageCleanMessagesEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  final channelId =
      bootstrap['channelId'];

  final accessHash =
      bootstrap['accessHash'];

  final rawMessageIds =
      bootstrap['messageIds'];

  final batchSize =
      bootstrap['batchSize'];

  if (eventPort is! SendPort ||
      channelId is! int ||
      accessHash is! int ||
      rawMessageIds is! List ||
      batchSize is! int ||
      batchSize <= 0) {
    return;
  }

  final messageIds =
      rawMessageIds
          .whereType<int>()
          .where((id) => id > 0)
          .toSet()
          .toList()
        ..sort();

  final telegramClient =
      TelegramClient.instance;

  try {
    final client =
        await telegramClient.connect();

    final channel =
        t.InputChannel(
      channelId: channelId,
      accessHash: accessHash,
    );

    int deleted = 0;

    for (int offset = 0;
        offset < messageIds.length;
        offset += batchSize) {
      final end =
          min(
        offset + batchSize,
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
        t.ChannelsDeleteMessages(
          channel: channel,
          id: batch,
        ),
      )
              .timeout(
        const Duration(
          seconds: 30,
        ),
      );

      final error =
          response.error;

      if (error != null) {
        throw Exception(
          error.errorMessage,
        );
      }

      deleted +=
          batch.length;

      eventPort.send(
        <String, dynamic>{
          'type': 'progress',
          'deleted': deleted,
        },
      );
    }

    eventPort.send(
      const <String, dynamic>{
        'type': 'completed',
      },
    );
  } catch (error, stackTrace) {
    eventPort.send(
      <String, dynamic>{
        'type': 'error',
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      },
    );
  }
}

class TelegramStorageCleanProgress {
  final String stage;
  final int deletedMessages;
  final int totalMessages;

  const TelegramStorageCleanProgress({
    required this.stage,
    required this.deletedMessages,
    required this.totalMessages,
  });

  double get progress =>
      totalMessages <= 0
          ? 1
          : (deletedMessages / totalMessages)
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();
}

class TelegramStorageCleanResult {
  final String packageId;
  final int catalogMessagesDeleted;
  final int filesMessagesDeleted;
  final bool stagingRemoved;
  final bool journalRemoved;

  const TelegramStorageCleanResult({
    required this.packageId,
    required this.catalogMessagesDeleted,
    required this.filesMessagesDeleted,
    required this.stagingRemoved,
    required this.journalRemoved,
  });

  int get totalMessagesDeleted =>
      catalogMessagesDeleted +
      filesMessagesDeleted;
}

class TelegramStorageCleanException
    implements Exception {
  final String message;

  const TelegramStorageCleanException(
    this.message,
  );

  @override
  String toString() => message;
}
