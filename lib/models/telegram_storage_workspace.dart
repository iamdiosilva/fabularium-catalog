import 'telegram_storage_channel.dart';

class TelegramStorageWorkspace {
  final TelegramStorageChannel? catalogChannel;

  final TelegramStorageChannel? filesChannel;

  const TelegramStorageWorkspace({
    required this.catalogChannel,
    required this.filesChannel,
  });

  const TelegramStorageWorkspace.empty()
      : catalogChannel = null,
        filesChannel = null;

  bool get hasCatalogChannel =>
      catalogChannel != null;

  bool get hasFilesChannel =>
      filesChannel != null;

  bool get isFullyConfigured =>
      catalogChannel != null &&
      filesChannel != null;

  bool get usesSameChannel =>
      catalogChannel != null &&
      filesChannel != null &&
      catalogChannel!.id ==
          filesChannel!.id;

  TelegramStorageWorkspace copyWith({
    TelegramStorageChannel? catalogChannel,
    TelegramStorageChannel? filesChannel,
    bool clearCatalogChannel = false,
    bool clearFilesChannel = false,
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
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'catalogChannel':
          catalogChannel?.toJson(),
      'filesChannel':
          filesChannel?.toJson(),
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
        return TelegramStorageChannel.fromJson(
          Map<String, dynamic>.from(
            raw,
          ),
        );
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
    );
  }
}