import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:t/t.dart' as t;

import '../../../models/telegram_storage_channel.dart';
import '../../../services/telegram_client.dart';

class TelegramStorageMessageGateway {
  static const int _batchSize = 100;

  Future<int> deleteMessages({
    required TelegramStorageChannel channel,
    required Iterable<int> messageIds,
    void Function(int deleted, int total)? onProgress,
  }) async {
    final ids = messageIds.where((id) => id > 0).toSet().toList()..sort();
    if (ids.isEmpty) return 0;

    final eventPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final completer = Completer<int>();
    Timer? exitGraceTimer;
    Isolate? isolate;

    late final StreamSubscription<dynamic> eventSubscription;
    late final StreamSubscription<dynamic> errorSubscription;
    late final StreamSubscription<dynamic> exitSubscription;

    eventSubscription = eventPort.listen((dynamic raw) {
      if (raw is! Map) return;
      final message = Map<dynamic, dynamic>.from(raw);
      switch (message['type']) {
        case 'progress':
          final deleted = message['deleted'];
          if (deleted is int) {
            onProgress?.call(deleted.clamp(0, ids.length), ids.length);
          }
          break;
        case 'completed':
          if (!completer.isCompleted) {
            onProgress?.call(ids.length, ids.length);
            completer.complete(ids.length);
          }
          break;
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
              TelegramStorageMessageGatewayException(
                message['error']?.toString() ??
                    'Telegram message operation failed.',
              ),
            );
          }
          break;
      }
    });

    errorSubscription = errorPort.listen((dynamic rawError) {
      if (completer.isCompleted) return;
      var message = rawError.toString();
      if (rawError is List && rawError.isNotEmpty) {
        message = rawError.first.toString();
      }
      completer.completeError(TelegramStorageMessageGatewayException(message));
    });

    exitSubscription = exitPort.listen((_) {
      if (completer.isCompleted) return;
      // completed/error and onExit use different ports. Give the normal event
      // a short chance to arrive before classifying the worker as failed.
      exitGraceTimer?.cancel();
      exitGraceTimer = Timer(const Duration(seconds: 1), () {
        if (!completer.isCompleted) {
          completer.completeError(
            const TelegramStorageMessageGatewayException(
              'Telegram message worker stopped unexpectedly.',
            ),
          );
        }
      });
    });

    try {
      isolate = await Isolate.spawn<Map<String, dynamic>>(
        _deleteMessagesEntryPoint,
        <String, dynamic>{
          'eventPort': eventPort.sendPort,
          'channelId': channel.id,
          'accessHash': channel.accessHash,
          'messageIds': ids,
          'batchSize': _batchSize,
        },
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'FabulariumStorageRepairDelete',
      );

      return await completer.future;
    } finally {
      exitGraceTimer?.cancel();
      isolate?.kill(priority: Isolate.immediate);
      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      eventPort.close();
      errorPort.close();
      exitPort.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _deleteMessagesEntryPoint(Map<String, dynamic> bootstrap) async {
  final eventPort = bootstrap['eventPort'];
  final channelId = bootstrap['channelId'];
  final accessHash = bootstrap['accessHash'];
  final rawIds = bootstrap['messageIds'];
  final batchSize = bootstrap['batchSize'];

  if (eventPort is! SendPort ||
      channelId is! int ||
      accessHash is! int ||
      rawIds is! List ||
      batchSize is! int ||
      batchSize <= 0) {
    return;
  }

  final ids = rawIds.whereType<int>().where((id) => id > 0).toSet().toList()
    ..sort();
  final telegramClient = TelegramClient.instance;

  try {
    final client = await telegramClient.connect();
    final channel = t.InputChannel(
      channelId: channelId,
      accessHash: accessHash,
    );

    var deleted = 0;
    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final end = min(offset + batchSize, ids.length);
      final batch = ids.sublist(offset, end);
      final response = await client
          .invoke(t.ChannelsDeleteMessages(channel: channel, id: batch))
          .timeout(const Duration(seconds: 30));

      if (response.error != null) {
        throw Exception(response.error!.errorMessage);
      }

      deleted += batch.length;
      eventPort.send(<String, dynamic>{
        'type': 'progress',
        'deleted': deleted,
      });
    }

    try {
      await telegramClient.disconnect();
    } catch (_) {}

    eventPort.send(const <String, dynamic>{'type': 'completed'});
  } catch (error, stackTrace) {
    try {
      await telegramClient.disconnect();
    } catch (_) {}
    eventPort.send(<String, dynamic>{
      'type': 'error',
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }
}

class TelegramStorageMessageGatewayException implements Exception {
  final String message;

  const TelegramStorageMessageGatewayException(this.message);

  @override
  String toString() => message;
}
