import 'telegram_storage_channel.dart';

const Object _journalUnset = Object();

enum TelegramStorageUploadStatus {
  preparing,
  uploading,
  failed,
  stored,
  removing,
}

extension TelegramStorageUploadStatusExtension on TelegramStorageUploadStatus {
  String get value {
    switch (this) {
      case TelegramStorageUploadStatus.preparing:
        return 'preparing';
      case TelegramStorageUploadStatus.uploading:
        return 'uploading';
      case TelegramStorageUploadStatus.failed:
        return 'failed';
      case TelegramStorageUploadStatus.stored:
        return 'stored';
      case TelegramStorageUploadStatus.removing:
        return 'removing';
    }
  }

  static TelegramStorageUploadStatus fromValue(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();

    for (final status in TelegramStorageUploadStatus.values) {
      if (status.value == normalized) {
        return status;
      }
    }

    return TelegramStorageUploadStatus.failed;
  }
}

class TelegramStorageUploadJournalGroup {
  final int groupIndex;
  final int? groupedId;
  final List<int> messageIds;
  final Map<int, int> partMessageIds;

  const TelegramStorageUploadJournalGroup({
    required this.groupIndex,
    required this.groupedId,
    required this.messageIds,
    required this.partMessageIds,
  });

  bool get isEmpty => messageIds.isEmpty;

  bool get isCompleted =>
      messageIds.isNotEmpty &&
      partMessageIds.isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'groupIndex': groupIndex,
      'groupedId': groupedId,
      'messageIds': messageIds,
      'partMessageIds': partMessageIds.map(
        (key, value) => MapEntry<String, int>(
          key.toString(),
          value,
        ),
      ),
    };
  }

  factory TelegramStorageUploadJournalGroup.fromJson(
    Map<String, dynamic> json,
  ) {
    final messageIds = <int>[];
    final rawMessageIds = json['messageIds'];

    if (rawMessageIds is List) {
      for (final value in rawMessageIds) {
        final id = _readJournalInt(value);

        if (id != null && id > 0) {
          messageIds.add(id);
        }
      }
    }

    final partMessageIds = <int, int>{};
    final rawPartMessageIds = json['partMessageIds'];

    if (rawPartMessageIds is Map) {
      for (final entry in rawPartMessageIds.entries) {
        final partIndex = int.tryParse(
          entry.key.toString(),
        );

        final messageId = _readJournalInt(
          entry.value,
        );

        if (partIndex != null &&
            messageId != null &&
            messageId > 0) {
          partMessageIds[partIndex] = messageId;
        }
      }
    }

    return TelegramStorageUploadJournalGroup(
      groupIndex:
          _readJournalInt(json['groupIndex']) ?? 0,
      groupedId:
          _readJournalInt(json['groupedId']),
      messageIds:
          messageIds,
      partMessageIds:
          partMessageIds,
    );
  }
}

class TelegramStorageUploadJournal {
  final String packageId;
  final String modelName;
  final String stagingDirectoryPath;
  final TelegramStorageChannel catalogChannel;
  final TelegramStorageChannel filesChannel;
  final TelegramStorageUploadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? galleryGroupedId;
  final List<int> galleryMessageIds;
  final Map<int, TelegramStorageUploadJournalGroup> fileGroups;
  final int? filesHeaderMessageId;
  final int? manifestMessageId;
  final String? lastError;

  /// File messages that were safe upload checkpoints and were superseded by
  /// a final Telegram media group. They are intentionally excluded from
  /// verification, but included in Clean and retried on Resume until removed.
  final List<int> pendingFileMessageIdsToDelete;

  const TelegramStorageUploadJournal({
    required this.packageId,
    required this.modelName,
    required this.stagingDirectoryPath,
    required this.catalogChannel,
    required this.filesChannel,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.galleryGroupedId,
    required this.galleryMessageIds,
    required this.fileGroups,
    this.filesHeaderMessageId,
    required this.manifestMessageId,
    required this.lastError,
    this.pendingFileMessageIdsToDelete = const <int>[],
  });

  bool get isPreparing =>
      status == TelegramStorageUploadStatus.preparing;

  bool get isUploading =>
      status == TelegramStorageUploadStatus.uploading;

  bool get isFailed =>
      status == TelegramStorageUploadStatus.failed;

  bool get isStored =>
      status == TelegramStorageUploadStatus.stored;

  bool get isRemoving =>
      status == TelegramStorageUploadStatus.removing;

  bool get hasGallery =>
      galleryMessageIds.isNotEmpty;

  bool get hasFilesHeader =>
      filesHeaderMessageId != null &&
      filesHeaderMessageId! > 0;

  bool get hasManifest =>
      manifestMessageId != null &&
      manifestMessageId! > 0;

  bool get hasPublishedFiles =>
      fileGroups.values.any(
        (group) => group.messageIds.isNotEmpty,
      );

  bool get hasPendingFileMessageCleanup =>
      pendingFileMessageIdsToDelete.any(
        (id) => id > 0,
      );

  List<int> get catalogMessageIds {
    final result = <int>{};

    for (final id in galleryMessageIds) {
      if (id > 0) {
        result.add(id);
      }
    }

    return result.toList()..sort();
  }

  /// Only final package messages are verified.
  List<int> get filesMessageIds {
    final result = <int>{};

    final headerId = filesHeaderMessageId;

    if (headerId != null && headerId > 0) {
      result.add(headerId);
    }

    final groups = fileGroups.values.toList()
      ..sort(
        (a, b) => a.groupIndex.compareTo(
          b.groupIndex,
        ),
      );

    for (final group in groups) {
      for (final id in group.messageIds) {
        if (id > 0) {
          result.add(id);
        }
      }
    }

    final manifestId = manifestMessageId;

    if (manifestId != null &&
        manifestId > 0) {
      result.add(manifestId);
    }

    if (isRemoving) {
      for (final id in pendingFileMessageIdsToDelete) {
        if (id > 0) {
          result.add(id);
        }
      }
    }

    return result.toList()..sort();
  }

  /// Clean must also remove superseded checkpoint messages when a previous
  /// cleanup was interrupted.
  List<int> get allMessageIds => <int>{
        ...catalogMessageIds,
        ...filesMessageIds,
        ...pendingFileMessageIdsToDelete.where(
          (id) => id > 0,
        ),
      }.toList()
        ..sort();

  int get publishedFileGroupCount =>
      fileGroups.values
          .where(
            (group) => group.messageIds.isNotEmpty,
          )
          .length;

  TelegramStorageUploadJournal copyWith({
    TelegramStorageUploadStatus? status,
    Object? galleryGroupedId = _journalUnset,
    List<int>? galleryMessageIds,
    Map<int, TelegramStorageUploadJournalGroup>? fileGroups,
    Object? filesHeaderMessageId = _journalUnset,
    Object? manifestMessageId = _journalUnset,
    Object? lastError = _journalUnset,
    List<int>? pendingFileMessageIdsToDelete,
  }) {
    return TelegramStorageUploadJournal(
      packageId: packageId,
      modelName: modelName,
      stagingDirectoryPath: stagingDirectoryPath,
      catalogChannel: catalogChannel,
      filesChannel: filesChannel,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      galleryGroupedId:
          identical(galleryGroupedId, _journalUnset)
              ? this.galleryGroupedId
              : galleryGroupedId as int?,
      galleryMessageIds:
          galleryMessageIds ??
              this.galleryMessageIds,
      fileGroups:
          fileGroups ??
              this.fileGroups,
      filesHeaderMessageId:
          identical(filesHeaderMessageId, _journalUnset)
              ? this.filesHeaderMessageId
              : filesHeaderMessageId as int?,
      manifestMessageId:
          identical(manifestMessageId, _journalUnset)
              ? this.manifestMessageId
              : manifestMessageId as int?,
      lastError:
          identical(lastError, _journalUnset)
              ? this.lastError
              : lastError as String?,
      pendingFileMessageIdsToDelete:
          pendingFileMessageIdsToDelete ??
              this.pendingFileMessageIdsToDelete,
    );
  }

  Map<String, dynamic> toJson() {
    final groups = fileGroups.values.toList()
      ..sort(
        (a, b) => a.groupIndex.compareTo(
          b.groupIndex,
        ),
      );

    return <String, dynamic>{
      'version': 3,
      'kind': 'fabularium-storage-upload-journal',
      'packageId': packageId,
      'modelName': modelName,
      'stagingDirectoryPath': stagingDirectoryPath,
      'status': status.value,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'catalogChannel': catalogChannel.toJson(),
      'filesChannel': filesChannel.toJson(),
      'gallery': <String, dynamic>{
        'groupedId': galleryGroupedId,
        'messageIds': galleryMessageIds,
      },
      'fileGroups': groups
          .map(
            (group) => group.toJson(),
          )
          .toList(),
      'filesHeaderMessageId': filesHeaderMessageId,
      'manifestMessageId': manifestMessageId,
      'pendingFileMessageIdsToDelete':
          pendingFileMessageIdsToDelete,
      'lastError': lastError,
    };
  }

  factory TelegramStorageUploadJournal.fromJson(
    Map<String, dynamic> json,
  ) {
    final catalogRaw = json['catalogChannel'];
    final filesRaw = json['filesChannel'];

    if (catalogRaw is! Map ||
        filesRaw is! Map) {
      throw const FormatException(
        'Storage journal channels are missing.',
      );
    }

    final catalogChannel =
        TelegramStorageChannel.fromJson(
      Map<String, dynamic>.from(
        catalogRaw,
      ),
    );

    final filesChannel =
        TelegramStorageChannel.fromJson(
      Map<String, dynamic>.from(
        filesRaw,
      ),
    );

    final rawGallery = json['gallery'];
    int? galleryGroupedId;
    final galleryMessageIds = <int>[];

    if (rawGallery is Map) {
      galleryGroupedId =
          _readJournalInt(
        rawGallery['groupedId'],
      );

      final rawMessageIds =
          rawGallery['messageIds'];

      if (rawMessageIds is List) {
        for (final value in rawMessageIds) {
          final id =
              _readJournalInt(
            value,
          );

          if (id != null &&
              id > 0) {
            galleryMessageIds.add(
              id,
            );
          }
        }
      }
    }

    final groups =
        <int, TelegramStorageUploadJournalGroup>{};

    final rawGroups =
        json['fileGroups'];

    if (rawGroups is List) {
      for (final rawGroup in rawGroups) {
        if (rawGroup is! Map) {
          continue;
        }

        try {
          final group =
              TelegramStorageUploadJournalGroup.fromJson(
            Map<String, dynamic>.from(
              rawGroup,
            ),
          );

          if (group.groupIndex > 0) {
            groups[group.groupIndex] =
                group;
          }
        } catch (_) {}
      }
    }

    final pendingDelete = <int>[];
    final rawPendingDelete =
        json['pendingFileMessageIdsToDelete'];

    if (rawPendingDelete is List) {
      for (final value in rawPendingDelete) {
        final id =
            _readJournalInt(
          value,
        );

        if (id != null &&
            id > 0 &&
            !pendingDelete.contains(id)) {
          pendingDelete.add(id);
        }
      }
    }

    pendingDelete.sort();

    final now = DateTime.now();

    return TelegramStorageUploadJournal(
      packageId:
          json['packageId']?.toString() ?? '',
      modelName:
          json['modelName']?.toString() ?? '',
      stagingDirectoryPath:
          json['stagingDirectoryPath']?.toString() ?? '',
      catalogChannel:
          catalogChannel,
      filesChannel:
          filesChannel,
      status:
          TelegramStorageUploadStatusExtension.fromValue(
        json['status'],
      ),
      createdAt:
          _readJournalDate(json['createdAt']) ??
              now,
      updatedAt:
          _readJournalDate(json['updatedAt']) ??
              now,
      galleryGroupedId:
          galleryGroupedId,
      galleryMessageIds:
          galleryMessageIds,
      fileGroups:
          groups,
      filesHeaderMessageId:
          _readJournalInt(
        json['filesHeaderMessageId'],
      ),
      manifestMessageId:
          _readJournalInt(
        json['manifestMessageId'],
      ),
      lastError:
          _readNullableJournalString(
        json['lastError'],
      ),
      pendingFileMessageIdsToDelete:
          pendingDelete,
    );
  }
}

int? _readJournalInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value?.toString() ?? '',
  );
}

DateTime? _readJournalDate(dynamic value) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(
    value.toString(),
  );
}

String? _readNullableJournalString(dynamic value) {
  if (value == null) {
    return null;
  }

  final text =
      value.toString().trim();

  return text.isEmpty
      ? null
      : text;
}
