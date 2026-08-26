import '../../../models/telegram_group.dart';
import '../../../services/telegram_client.dart';
import '../../../services/telegram_service.dart';
import '../../../services/telegram_storage_workspace_service.dart';
import '../domain/entities/telegram_catalog_entry.dart';
import '../domain/repositories/telegram_catalog_repository.dart';
import 'telegram_catalog_caption_parser.dart';

class TelegramCatalogRepositoryImpl
    implements TelegramCatalogRepository {
  final TelegramStorageWorkspaceService
      workspaceService;
  final TelegramService telegramService;
  final TelegramCatalogCaptionParser parser;

  TelegramCatalogRepositoryImpl({
    TelegramStorageWorkspaceService?
        workspaceService,
    TelegramService? telegramService,
    TelegramCatalogCaptionParser? parser,
  })  : workspaceService =
            workspaceService ??
                TelegramStorageWorkspaceService
                    .instance,
        telegramService =
            telegramService ??
                TelegramService.instance,
        parser =
            parser ??
                TelegramCatalogCaptionParser();

  @override
  Future<TelegramCatalogPageResult>
      loadPage({
    int limit = 100,
    int offsetId = 0,
  }) async {
    final workspace =
        await workspaceService.load();

    final channel =
        workspace.catalogChannel;

    if (channel == null) {
      throw const TelegramCatalogRepositoryException(
        'Catalog Channel is not configured. '
        'Open Telegram Storage Settings first.',
      );
    }

    await TelegramClient.instance.connect();

    final group = TelegramGroup(
      id: channel.id,
      title: channel.title,
      accessHash: channel.accessHash,
      isChannel: true,
    );

    final messages =
        await telegramService.getMessages(
      group,
      limit: limit,
      offsetId: offsetId,
    );

    final entries =
        <TelegramCatalogEntry>[];

    for (final message in messages) {
      final entry = parser.parse(
        message,
      );

      if (entry != null) {
        entries.add(
          entry,
        );
      }
    }

    final nextOffsetId =
        messages.isEmpty
            ? offsetId
            : messages.last.id;

    return TelegramCatalogPageResult(
      channelTitle: channel.title,
      entries: entries,
      nextOffsetId: nextOffsetId,
      hasMore: messages.length >= limit,
    );
  }
}

class TelegramCatalogRepositoryException
    implements Exception {
  final String message;

  const TelegramCatalogRepositoryException(
    this.message,
  );

  @override
  String toString() => message;
}
