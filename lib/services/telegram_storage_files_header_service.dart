import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';

class TelegramStorageFilesHeaderService {
  TelegramStorageFilesHeaderService._();

  static final TelegramStorageFilesHeaderService instance =
      TelegramStorageFilesHeaderService._();

  final TelegramClient _telegramClient = TelegramClient.instance;

  Future<int> sendHeader({
    required TelegramStorageChannel channel,
    required String text,
    required String randomIdKey,
  }) async {
    final message = text.trim();

    if (message.isEmpty) {
      throw const TelegramStorageFilesHeaderException(
        'Telegram Files header cannot be empty.',
      );
    }

    final randomId = _stableRandomId(randomIdKey);
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _resetControlConnection();

        final client = await _telegramClient.connect();
        final peer = t.InputPeerChannel(
          channelId: channel.id,
          accessHash: channel.accessHash,
        );

        final response = await client
            .invoke(
              t.MessagesSendMessage(
                noWebpage: true,
                silent: true,
                background: true,
                clearDraft: false,
                noforwards: false,
                updateStickersetsOrder: false,
                invertMedia: false,
                allowPaidFloodskip: false,
                peer: peer,
                message: message,
                randomId: randomId,
              ),
            )
            .timeout(
              const Duration(minutes: 2),
            );

        if (response.error != null) {
          throw Exception(response.error!.errorMessage);
        }

        return _extractSentMessageId(
          updates: response.result,
          randomId: randomId,
        );
      } catch (error) {
        lastError = error;

        if (attempt >= 3) {
          break;
        }

        await Future<void>.delayed(
          Duration(seconds: attempt),
        );
      }
    }

    throw TelegramStorageFilesHeaderException(
      'Could not publish Telegram Files header after 3 attempts: '
      '$lastError',
    );
  }

  Future<void> _resetControlConnection() async {
    try {
      await _telegramClient.disconnect();
    } catch (_) {}
  }

  static int _stableRandomId(String value) {
    const int offset = 1469598103934665603;
    const int prime = 1099511628211;
    const int mask = 0x7FFFFFFFFFFFFFFF;

    int hash = offset;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & mask;
    }

    return hash == 0 ? 1 : hash;
  }
}

int _extractSentMessageId({
  required dynamic updates,
  required int randomId,
}) {
  if (updates == null) {
    throw const TelegramStorageFilesHeaderException(
      'Telegram returned no updates for the Files header.',
    );
  }

  if (updates.runtimeType.toString() == 'UpdateShortSentMessage') {
    try {
      final id = updates.id as int;

      if (id > 0) {
        return id;
      }
    } catch (_) {}
  }

  int? mappedId;
  final fallback = <int>[];
  List<dynamic> rawUpdates = <dynamic>[];

  try {
    rawUpdates = List<dynamic>.from(
      updates.updates as List,
    );
  } catch (_) {}

  for (final dynamic update in rawUpdates) {
    final type = update.runtimeType.toString();

    if (type == 'UpdateMessageID') {
      try {
        if (update.randomId as int == randomId) {
          mappedId = update.id as int;
        }
      } catch (_) {}

      continue;
    }

    if (type == 'UpdateNewChannelMessage' ||
        type == 'UpdateNewMessage') {
      try {
        final dynamic message = update.message;
        final id = message.id as int;

        if (id > 0 && !fallback.contains(id)) {
          fallback.add(id);
        }
      } catch (_) {}
    }
  }

  if (mappedId != null && mappedId > 0) {
    return mappedId;
  }

  if (fallback.length == 1) {
    return fallback.single;
  }

  throw const TelegramStorageFilesHeaderException(
    'Could not determine the Telegram message ID of the Files header.',
  );
}

class TelegramStorageFilesHeaderException implements Exception {
  final String message;

  const TelegramStorageFilesHeaderException(
    this.message,
  );

  @override
  String toString() => message;
}
