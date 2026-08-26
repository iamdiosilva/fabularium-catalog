import '../../../models/telegram_storage_upload_journal.dart';
import '../../../services/telegram_storage_upload_journal_service.dart';
import '../../../services/telegram_storage_verification_service.dart';
import '../data/telegram_storage_message_gateway.dart';
import '../domain/entities/storage_repair_result.dart';

typedef TelegramStorageRepairProgressCallback = void Function(
  String stage,
  double progress,
);

class TelegramStorageRepairService {
  final TelegramStorageVerificationService verificationService;
  final TelegramStorageUploadJournalService journalService;
  final TelegramStorageMessageGateway messageGateway;

  TelegramStorageRepairService({
    TelegramStorageVerificationService? verificationService,
    TelegramStorageUploadJournalService? journalService,
    TelegramStorageMessageGateway? messageGateway,
  })  : verificationService =
            verificationService ?? TelegramStorageVerificationService.instance,
        journalService =
            journalService ?? TelegramStorageUploadJournalService.instance,
        messageGateway = messageGateway ?? TelegramStorageMessageGateway();

  Future<StorageRepairResult> repair({
    required TelegramStorageUploadJournal journal,
    TelegramStorageRepairProgressCallback? onProgress,
  }) async {
    if (journal.isRemoving) {
      throw const TelegramStorageRepairException(
        'A package being removed cannot be repaired.',
      );
    }

    _report(onProgress, 'Verifying recorded Telegram messages...', 0.05);

    final verification = await verificationService.verifyAndUpdate(
      journal: journal,
      onProgress: (progress) {
        _report(
          onProgress,
          progress.stage,
          0.05 + progress.progress * 0.45,
        );
      },
    );

    var current = verification.journal;

    if (verification.allPresent) {
      if (!current.isStored) {
        current = await journalService.markStored(current);
      }
      _report(onProgress, 'Package is already healthy.', 1);
      return StorageRepairResult(
        packageId: current.packageId,
        alreadyHealthy: true,
        galleryMessagesRemoved: 0,
        fileMessagesRemoved: 0,
        fileGroupsReset: 0,
        galleryReset: false,
        manifestReset: false,
      );
    }

    final missingCatalog = verification.missingCatalogMessageIds.toSet();
    final missingFiles = verification.missingFilesMessageIds.toSet();

    var galleryReset = false;
    var manifestReset = false;
    var galleryDeleted = 0;
    var filesDeleted = 0;
    var fileGroupsReset = 0;

    var galleryMessageIds = List<int>.from(current.galleryMessageIds);
    var galleryGroupedId = current.galleryGroupedId;
    final groups = Map<int, TelegramStorageUploadJournalGroup>.from(
      current.fileGroups,
    );
    var manifestMessageId = current.manifestMessageId;

    final galleryIsPartial =
        galleryMessageIds.any(missingCatalog.contains);

    if (galleryIsPartial) {
      final remaining = galleryMessageIds
          .where((id) => !missingCatalog.contains(id))
          .toList();
      _report(
        onProgress,
        'Resetting partial Catalog gallery...',
        0.55,
      );
      galleryDeleted = await messageGateway.deleteMessages(
        channel: current.catalogChannel,
        messageIds: remaining,
      );
      galleryMessageIds = <int>[];
      galleryGroupedId = null;
      galleryReset = true;
    }

    final orderedGroups = groups.values.toList()
      ..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));

    for (var i = 0; i < orderedGroups.length; i++) {
      final group = orderedGroups[i];
      final groupIsPartial = group.messageIds.any(missingFiles.contains);
      if (!groupIsPartial) continue;

      final remaining = group.messageIds
          .where((id) => !missingFiles.contains(id))
          .toList();
      _report(
        onProgress,
        'Resetting partial Files group ${group.groupIndex}...',
        0.6 + ((i + 1) / orderedGroups.length) * 0.25,
      );
      filesDeleted += await messageGateway.deleteMessages(
        channel: current.filesChannel,
        messageIds: remaining,
      );
      groups.remove(group.groupIndex);
      fileGroupsReset++;
    }

    if (manifestMessageId != null && missingFiles.contains(manifestMessageId)) {
      manifestMessageId = null;
      manifestReset = true;
    }

    // Gallery and file-group message IDs are embedded in the final manifest.
    // When Repair resets any of those groups, the old manifest becomes stale
    // even when the manifest message itself still exists on Telegram. Delete
    // that stale manifest so Resume is forced to publish a fresh V3 manifest.
    if ((galleryReset || fileGroupsReset > 0) && manifestMessageId != null) {
      _report(
        onProgress,
        'Removing stale Storage V3 manifest...',
        0.9,
      );

      filesDeleted += await messageGateway.deleteMessages(
        channel: current.filesChannel,
        messageIds: <int>[manifestMessageId],
      );

      manifestMessageId = null;
      manifestReset = true;
    }

    // If the journal was structurally incomplete there may be no IDs to
    // reset. That is still a valid repair: clearing the REMOTE_MISSING marker
    // enables Resume to build the missing groups/manifest from local staging.
    current = current.copyWith(
      status: TelegramStorageUploadStatus.failed,
      galleryGroupedId: galleryGroupedId,
      galleryMessageIds: galleryMessageIds,
      fileGroups: groups,
      manifestMessageId: manifestMessageId,
      lastError: 'Repair completed. Resume will upload only the reset or '
          'missing Storage V3 groups.',
    );

    await journalService.save(current);
    _report(onProgress, 'Repair completed. Resume is available.', 1);

    return StorageRepairResult(
      packageId: current.packageId,
      alreadyHealthy: false,
      galleryMessagesRemoved: galleryDeleted,
      fileMessagesRemoved: filesDeleted,
      fileGroupsReset: fileGroupsReset,
      galleryReset: galleryReset,
      manifestReset: manifestReset,
    );
  }

  void _report(
    TelegramStorageRepairProgressCallback? callback,
    String stage,
    double progress,
  ) {
    callback?.call(stage, progress.clamp(0.0, 1.0));
  }
}

class TelegramStorageRepairException implements Exception {
  final String message;

  const TelegramStorageRepairException(this.message);

  @override
  String toString() => message;
}
