import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/telegram_storage_upload_journal.dart';
import '../../../models/telegram_storage_workspace.dart';
import '../../../services/telegram_storage_clean_service.dart';
import '../../../services/telegram_storage_package_recovery_service.dart';
import '../../../services/telegram_storage_package_uploader.dart';
import '../../../services/telegram_storage_upload_journal_service.dart';
import '../../../services/telegram_storage_verification_service.dart';
import '../domain/entities/storage_repair_result.dart';
import 'telegram_storage_repair_service.dart';

class TelegramStorageRecoveryController extends ChangeNotifier {
  final TelegramStorageUploadJournalService journalService;
  final TelegramStoragePackageRecoveryService packageRecoveryService;
  final TelegramStoragePackageUploader packageUploader;
  final TelegramStorageCleanService cleanService;
  final TelegramStorageVerificationService verificationService;
  final TelegramStorageRepairService repairService;

  TelegramStorageRecoveryController({
    TelegramStorageUploadJournalService? journalService,
    TelegramStoragePackageRecoveryService? packageRecoveryService,
    TelegramStoragePackageUploader? packageUploader,
    TelegramStorageCleanService? cleanService,
    TelegramStorageVerificationService? verificationService,
    TelegramStorageRepairService? repairService,
  })  : journalService =
            journalService ?? TelegramStorageUploadJournalService.instance,
        packageRecoveryService = packageRecoveryService ??
            TelegramStoragePackageRecoveryService.instance,
        packageUploader =
            packageUploader ?? TelegramStoragePackageUploader.instance,
        cleanService = cleanService ?? TelegramStorageCleanService.instance,
        verificationService = verificationService ??
            TelegramStorageVerificationService.instance,
        repairService = repairService ?? TelegramStorageRepairService();

  List<TelegramStorageUploadJournal> journals =
      <TelegramStorageUploadJournal>[];
  bool isLoading = true;
  bool isUploading = false;
  bool isCleaning = false;
  bool isRepairing = false;
  String? activePackageId;
  double progress = 0;
  String progressStage = '';
  String? progressFileName;
  String? error;
  String? status;
  TelegramStoragePackageUploadResult? lastUploadResult;
  StorageRepairResult? lastRepairResult;

  bool get isBusy => isUploading || isCleaning || isRepairing;

  bool isRemoteMissing(TelegramStorageUploadJournal journal) =>
      verificationService.isRemoteMissingJournal(journal);

  bool hasRecoveryDescriptor(TelegramStorageUploadJournal journal) =>
      packageRecoveryService.hasRecoveryDescriptor(journal);

  Future<void> load({bool showStatus = false}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      journals = await journalService.listIncomplete();
      isLoading = false;
      if (showStatus) {
        status = journals.isEmpty
            ? 'No incomplete uploads were found.'
            : '${journals.length} incomplete upload'
                '${journals.length == 1 ? '' : 's'} found.';
      }
      notifyListeners();
    } catch (e) {
      isLoading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> openJournalFolder() => journalService.openJournalFolder();

  Future<void> resume(TelegramStorageUploadJournal journal) async {
    if (isBusy || journal.isRemoving) return;
    if (isRemoteMissing(journal)) {
      throw const TelegramStorageRecoveryActionException(
        'Repair this package before Resume because Telegram messages are missing.',
      );
    }
    if (!hasRecoveryDescriptor(journal)) {
      throw const TelegramStorageRecoveryActionException(
        'No local package recovery descriptor is available for this upload.',
      );
    }

    final package = await packageRecoveryService.loadForJournal(journal);
    final workspace = TelegramStorageWorkspace(
      catalogChannel: journal.catalogChannel,
      filesChannel: journal.filesChannel,
    );

    isUploading = true;
    activePackageId = journal.packageId;
    progress = 0;
    progressStage = 'Resuming package upload...';
    progressFileName = null;
    error = null;
    status = null;
    lastUploadResult = null;
    notifyListeners();

    var journalSynced = false;
    try {
      final result = await packageUploader.uploadPackage(
        workspace: workspace,
        package: package,
        onProgress: (value) {
          if (!journalSynced) {
            journalSynced = true;
            unawaited(_refreshJournalsSilently());
          }
          progress = value.overallProgress;
          progressStage = value.stage;
          progressFileName = value.currentFileName;
          notifyListeners();
        },
      );

      isUploading = false;
      activePackageId = null;
      progress = 1;
      progressStage = 'Recovery completed successfully.';
      lastUploadResult = result;
      status = result.alreadyUploaded
          ? 'The package was already complete. Nothing was duplicated.'
          : 'Upload resumed successfully. Manifest message ID: '
              '${result.manifestMessageId}.';
      await _refreshJournalsSilently();
      notifyListeners();
    } catch (e) {
      isUploading = false;
      activePackageId = null;
      error = e.toString();
      status = 'Resume stopped. Completed groups remain persisted safely.';
      await _refreshJournalsSilently();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clean(TelegramStorageUploadJournal journal) async {
    if (isBusy || journal.isStored) return;

    var current = journal;
    if (!journal.isRemoving) {
      current = await journalService.markRemoving(journal);
    }

    _replaceJournal(current);
    isCleaning = true;
    activePackageId = journal.packageId;
    error = null;
    status = 'Preparing cleanup for ${journal.modelName}...';
    notifyListeners();

    try {
      final result = await cleanService.clean(
        journal: current,
        markRemoving: false,
        onProgress: (value) {
          status = value.totalMessages <= 0
              ? value.stage
              : '${value.stage} '
                  '${value.deletedMessages}/${value.totalMessages}';
          notifyListeners();
        },
      );

      isCleaning = false;
      activePackageId = null;
      status = 'Clean completed. ${result.totalMessagesDeleted} Telegram message'
          '${result.totalMessagesDeleted == 1 ? '' : 's'} removed.';
      await _refreshJournalsSilently();
      notifyListeners();
    } catch (e) {
      isCleaning = false;
      activePackageId = null;
      error = e.toString();
      status = 'Clean stopped. The journal remains available so the operation '
          'can be retried safely.';
      await _refreshJournalsSilently();
      notifyListeners();
      rethrow;
    }
  }

  Future<StorageRepairResult> repair(
    TelegramStorageUploadJournal journal,
  ) async {
    if (isBusy || journal.isRemoving) {
      throw const TelegramStorageRecoveryActionException(
        'This package is currently busy and cannot be repaired.',
      );
    }

    if (!hasRecoveryDescriptor(journal)) {
      throw const TelegramStorageRecoveryActionException(
        'Repair requires the local recovery descriptor so Resume can rebuild '
        'missing groups safely.',
      );
    }

    isRepairing = true;
    activePackageId = journal.packageId;
    progress = 0;
    progressStage = 'Starting Telegram repair...';
    error = null;
    status = null;
    lastRepairResult = null;
    notifyListeners();

    try {
      final result = await repairService.repair(
        journal: journal,
        onProgress: (stage, value) {
          progressStage = stage;
          progress = value;
          notifyListeners();
        },
      );

      isRepairing = false;
      activePackageId = null;
      lastRepairResult = result;
      status = result.alreadyHealthy
          ? 'Telegram package is healthy. No repair was required.'
          : 'Repair completed. Resume can now upload the missing groups.';
      await _refreshJournalsSilently();
      notifyListeners();
      return result;
    } catch (e) {
      isRepairing = false;
      activePackageId = null;
      error = e.toString();
      status = 'Repair stopped. The journal was kept for another attempt.';
      await _refreshJournalsSilently();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _refreshJournalsSilently() async {
    try {
      journals = await journalService.listIncomplete();
    } catch (_) {}
  }

  void _replaceJournal(TelegramStorageUploadJournal journal) {
    final index = journals.indexWhere((item) => item.packageId == journal.packageId);
    if (index < 0) return;
    final updated = List<TelegramStorageUploadJournal>.from(journals);
    updated[index] = journal;
    journals = updated;
  }
}

class TelegramStorageRecoveryActionException implements Exception {
  final String message;

  const TelegramStorageRecoveryActionException(this.message);

  @override
  String toString() => message;
}
