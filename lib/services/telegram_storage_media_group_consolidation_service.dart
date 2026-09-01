import 'dart:math';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';

class TelegramStorageExistingMediaGroupResult {
  final List<int> messageIds;
  final int? groupedId;

  const TelegramStorageExistingMediaGroupResult({
    required this.messageIds,
    required this.groupedId,
  });
}

/// Republishes already-published Telegram documents without uploading bytes.
///
/// For two to ten documents this produces a Telegram media group with
/// messages.sendMultiMedia. For a single document it uses messages.sendMedia.
/// Source messages are fetched first so fresh Document file references are used.
class TelegramStorageMediaGroupConsolidationService {
  TelegramStorageMediaGroupConsolidationService._();

  static final TelegramStorageMediaGroupConsolidationService instance =
      TelegramStorageMediaGroupConsolidationService._();

  final TelegramClient _telegramClient = TelegramClient.instance;

  Future<TelegramStorageExistingMediaGroupResult> groupExistingDocuments({
    required TelegramStorageChannel channel,
    required List<int> sourceMessageIds,
    required List<String> randomIdKeys,
    required String caption,
  }) async {
    final ids = sourceMessageIds.where((id) => id > 0).toList();

    if (ids.isEmpty) {
      throw const TelegramStorageMediaGroupConsolidationException(
        'At least one Telegram document is required for consolidation.',
      );
    }

    if (ids.length > 10) {
      throw const TelegramStorageMediaGroupConsolidationException(
        'Telegram media groups support at most 10 documents.',
      );
    }

    if (ids.length != randomIdKeys.length) {
      throw const TelegramStorageMediaGroupConsolidationException(
        'The consolidation random ID count does not match the document count.',
      );
    }

    try {
      await _resetControlConnection();
      final client = await _telegramClient.connect();

      final inputChannel = t.InputChannel(
        channelId: channel.id,
        accessHash: channel.accessHash,
      );

      final peer = t.InputPeerChannel(
        channelId: channel.id,
        accessHash: channel.accessHash,
      );

      final response = await client
          .invoke(
            t.ChannelsGetMessages(
              channel: inputChannel,
              id: ids
                  .map<t.InputMessageBase>(
                    (id) => t.InputMessageID(id: id),
                  )
                  .toList(),
            ),
          )
          .timeout(
            const Duration(seconds: 60),
          );

      if (response.error != null) {
        throw Exception(response.error!.errorMessage);
      }

      final dynamic result = response.result;

      if (result == null) {
        throw const TelegramStorageMediaGroupConsolidationException(
          'Telegram returned an empty source-message response.',
        );
      }

      List<dynamic> rawMessages;

      try {
        rawMessages = List<dynamic>.from(
          result.messages as List,
        );
      } catch (_) {
        throw const TelegramStorageMediaGroupConsolidationException(
          'Telegram returned an unsupported source-message response.',
        );
      }

      final messagesById = <int, dynamic>{};

      for (final dynamic message in rawMessages) {
        if (message is t.MessageEmpty) {
          continue;
        }

        try {
          final id = message.id as int;
          messagesById[id] = message;
        } catch (_) {}
      }

      final media = <t.InputSingleMedia>[];
      final randomIds = <int>[];

      for (var index = 0; index < ids.length; index++) {
        final sourceId = ids[index];
        final dynamic message = messagesById[sourceId];

        if (message == null) {
          throw TelegramStorageMediaGroupConsolidationException(
            'Telegram source message $sourceId was not found.',
          );
        }

        dynamic document;

        try {
          final dynamic messageMedia = message.media;

          if (messageMedia == null ||
              messageMedia.runtimeType.toString() != 'MessageMediaDocument') {
            throw const FormatException('Message is not a document.');
          }

          document = messageMedia.document;
        } catch (e) {
          throw TelegramStorageMediaGroupConsolidationException(
            'Telegram source message $sourceId does not contain a reusable '
            'document: $e',
          );
        }

        if (document == null ||
            document.runtimeType.toString() != 'Document') {
          throw TelegramStorageMediaGroupConsolidationException(
            'Telegram source message $sourceId returned an invalid document.',
          );
        }

        final randomId = _stableRandomId(
          randomIdKeys[index],
        );

        randomIds.add(randomId);

        media.add(
          t.InputSingleMedia(
            media: t.InputMediaDocument(
              spoiler: false,
              id: t.InputDocument(
                id: document.id as int,
                accessHash: document.accessHash as int,
                fileReference: document.fileReference,
              ),
            ),
            randomId: randomId,
            message: index == 0 ? caption : '',
          ),
        );
      }

      dynamic publish;

      if (media.length == 1) {
        final item = media.single;

        publish = await client
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
            .timeout(
              const Duration(minutes: 2),
            );
      } else {
        publish = await client
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
                multiMedia: media,
              ),
            )
            .timeout(
              const Duration(minutes: 2),
            );
      }

      if (publish.error != null) {
        throw Exception(publish.error!.errorMessage);
      }

      final parsed = _extractSentGroup(
        updates: publish.result,
        randomIds: randomIds,
      );

      return TelegramStorageExistingMediaGroupResult(
        messageIds: parsed.messageIds,
        groupedId: parsed.groupedId,
      );
    } catch (e) {
      if (e is TelegramStorageMediaGroupConsolidationException) {
        rethrow;
      }

      throw TelegramStorageMediaGroupConsolidationException(
        'Could not consolidate Telegram documents into a media group: $e',
      );
    } finally {
      try {
        await _telegramClient.disconnect();
      } catch (_) {}
    }
  }

  Future<int> deleteMessages({
    required TelegramStorageChannel channel,
    required Iterable<int> messageIds,
  }) async {
    final ids = messageIds.where((id) => id > 0).toSet().toList()..sort();

    if (ids.isEmpty) {
      return 0;
    }

    try {
      await _resetControlConnection();
      final client = await _telegramClient.connect();

      final inputChannel = t.InputChannel(
        channelId: channel.id,
        accessHash: channel.accessHash,
      );

      var deleted = 0;
      const batchSize = 100;

      for (var offset = 0; offset < ids.length; offset += batchSize) {
        final end = min<int>(
          offset + batchSize,
          ids.length,
        );

        final batch = ids.sublist(
          offset,
          end,
        );

        final response = await client
            .invoke(
              t.ChannelsDeleteMessages(
                channel: inputChannel,
                id: batch,
              ),
            )
            .timeout(
              const Duration(seconds: 60),
            );

        if (response.error != null) {
          throw Exception(response.error!.errorMessage);
        }

        deleted += batch.length;
      }

      return deleted;
    } catch (e) {
      throw TelegramStorageMediaGroupConsolidationException(
        'Could not remove temporary Telegram checkpoint messages: $e',
      );
    } finally {
      try {
        await _telegramClient.disconnect();
      } catch (_) {}
    }
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

_SentMediaGroup _extractSentGroup({
  required dynamic updates,
  required List<int> randomIds,
}) {
  if (updates == null) {
    throw const TelegramStorageMediaGroupConsolidationException(
      'Telegram returned no updates for the consolidated media group.',
    );
  }

  if (updates.runtimeType.toString() == 'UpdateShortSentMessage') {
    try {
      final id = updates.id as int;

      if (id > 0 && randomIds.length == 1) {
        return _SentMediaGroup(
          messageIds: <int>[id],
          groupedId: null,
        );
      }
    } catch (_) {}
  }

  final mapping = <int, int>{};
  final fallback = <int>[];
  int? groupedId;

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
        mapping[update.randomId as int] = update.id as int;
      } catch (_) {}

      continue;
    }

    if (type == 'UpdateNewChannelMessage' ||
        type == 'UpdateNewMessage') {
      try {
        final dynamic message = update.message;
        final id = message.id as int;

        if (!fallback.contains(id)) {
          fallback.add(id);
        }

        final dynamic rawGroupedId = message.groupedId;

        if (rawGroupedId is int) {
          groupedId ??= rawGroupedId;
        }
      } catch (_) {}
    }
  }

  final ordered = <int>[];
  var complete = true;

  for (final randomId in randomIds) {
    final id = mapping[randomId];

    if (id == null) {
      complete = false;
      break;
    }

    ordered.add(id);
  }

  if (complete && ordered.length == randomIds.length) {
    return _SentMediaGroup(
      messageIds: ordered,
      groupedId: groupedId,
    );
  }

  fallback.sort();

  if (fallback.length != randomIds.length) {
    throw const TelegramStorageMediaGroupConsolidationException(
      'Could not determine the message IDs of the consolidated Telegram group.',
    );
  }

  return _SentMediaGroup(
    messageIds: fallback,
    groupedId: groupedId,
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

class TelegramStorageMediaGroupConsolidationException implements Exception {
  final String message;

  const TelegramStorageMediaGroupConsolidationException(
    this.message,
  );

  @override
  String toString() => message;
}
