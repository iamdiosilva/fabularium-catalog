import 'telegram_storage_channel.dart';

class TelegramStorageWorkspace {
  final TelegramStorageChannel? catalogChannel;
  final TelegramStorageChannel? filesChannel;
  final TelegramStorageChannel? pendingChannel;

  const TelegramStorageWorkspace({
    required this.catalogChannel,
    required this.filesChannel,
    this.pendingChannel,
  });

  const TelegramStorageWorkspace.empty()
      : catalogChannel = null,
        filesChannel = null,
        pendingChannel = null;

  bool get hasCatalogChannel =>
      catalogChannel != null;

  bool get hasFilesChannel =>
      filesChannel != null;

  bool get hasPendingChannel =>
      pendingChannel != null;

  /// Kept compatible with the current Telegram Storage uploader.
  /// Official local/admin uploads still require only Catalog + Files.
  bool get isFullyConfigured =>
      catalogChannel != null &&
      filesChannel != null;

  /// Community publishing additionally requires the private Pending channel.
  bool get isCommunityConfigured =>
      isFullyConfigured &&
      pendingChannel != null;

  bool get usesSameChannel {
    final ids = <int>[];

    for (final channel in <TelegramStorageChannel?>[
      catalogChannel,
      filesChannel,
      pendingChannel,
    ]) {
      if (channel != null) {
        ids.add(channel.id);
      }
    }

    return ids.toSet().length !=
        ids.length;
  }

  TelegramStorageWorkspace copyWith({
    TelegramStorageChannel? catalogChannel,
    TelegramStorageChannel? filesChannel,
    TelegramStorageChannel? pendingChannel,
    bool clearCatalogChannel = false,
    bool clearFilesChannel = false,
    bool clearPendingChannel = false,
  }) {
    return TelegramStorageWorkspace(
      catalogChannel:
          clearCatalogChannel
              ? null
              : catalogChannel ??
                  this.catalogChannel,
      filesChannel:
          clearFilesChannel
              ? null
              : filesChannel ??
                  this.filesChannel,
      pendingChannel:
          clearPendingChannel
              ? null
              : pendingChannel ??
                  this.pendingChannel,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'catalogChannel':
          catalogChannel?.toJson(),
      'filesChannel':
          filesChannel?.toJson(),
      'pendingChannel':
          pendingChannel?.toJson(),
    };
  }

  factory TelegramStorageWorkspace.fromJson(
    Map<String, dynamic> json,
  ) {
    TelegramStorageChannel? readChannel(
      dynamic raw,
    ) {
      if (raw is! Map) {
        return null;
      }

      try {
        final channel =
            TelegramStorageChannel.fromJson(
          Map<String, dynamic>.from(raw),
        );

        if (channel.id <= 0 ||
            channel.accessHash == 0) {
          return null;
        }

        return channel;
      } catch (_) {
        return null;
      }
    }

    return TelegramStorageWorkspace(
      catalogChannel:
          readChannel(
        json['catalogChannel'],
      ),
      filesChannel:
          readChannel(
        json['filesChannel'],
      ),
      pendingChannel:
          readChannel(
        json['pendingChannel'],
      ),
    );
  }
}
