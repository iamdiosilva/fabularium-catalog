import '../../../../models/catalog_model.dart';
import '../../../../models/telegram_storage_upload_journal.dart';
import '../../../../services/catalog_model_identity_service.dart';
import '../../../../services/telegram_storage_model_registry_service.dart';
import '../../../../services/telegram_storage_verification_service.dart';
import '../../domain/entities/catalog_telegram_status.dart';
import '../../domain/repositories/catalog_telegram_status_repository.dart';

class LocalTelegramStatusRepository
    implements CatalogTelegramStatusRepository {
  final CatalogModelIdentityService identityService;
  final TelegramStorageModelRegistryService registryService;
  final TelegramStorageVerificationService verificationService;

  LocalTelegramStatusRepository({
    CatalogModelIdentityService? identityService,
    TelegramStorageModelRegistryService? registryService,
    TelegramStorageVerificationService? verificationService,
  })  : identityService =
            identityService ??
                CatalogModelIdentityService.instance,
        registryService =
            registryService ??
                TelegramStorageModelRegistryService.instance,
        verificationService =
            verificationService ??
                TelegramStorageVerificationService.instance;

  @override
  Future<CatalogTelegramStatus> readLocalStatus(
    CatalogModel model,
  ) async {
    final modelId =
        await identityService.readPersistedModelId(
      model,
    );

    if (modelId == null ||
        modelId.isEmpty) {
      return const CatalogTelegramStatus.notUploaded();
    }

    final status =
        await registryService.getStatus(
      model: model,
      modelId: modelId,
    );

    return _mapJournal(
      status.journal,
    );
  }

  @override
  Future<CatalogTelegramStatus> verifyStoredStatus(
    CatalogModel model,
  ) async {
    final modelId =
        await identityService.readPersistedModelId(
      model,
    );

    if (modelId == null ||
        modelId.isEmpty) {
      return const CatalogTelegramStatus.notUploaded();
    }

    var status =
        await registryService.getStatus(
      model: model,
      modelId: modelId,
    );

    final journal =
        status.journal;

    if (journal == null) {
      return const CatalogTelegramStatus.notUploaded();
    }

    if (!journal.isStored) {
      return _mapJournal(
        journal,
      );
    }

    try {
      final verification =
          await verificationService.verifyAndUpdate(
        journal: journal,
      );

      if (verification.allPresent) {
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.uploaded,
          packageId:
              journal.packageId,
          remoteVerified:
              true,
        );
      }

      status =
          await registryService.getStatus(
        model: model,
        modelId: modelId,
      );

      final updatedJournal =
          status.journal;

      if (verificationService
          .isRemoteMissingJournal(
        updatedJournal,
      )) {
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.remoteMissing,
          packageId:
              updatedJournal?.packageId ??
                  journal.packageId,
          detail:
              updatedJournal?.lastError,
        );
      }

      return _mapJournal(
        updatedJournal,
      );
    } catch (error) {
      return CatalogTelegramStatus(
        state:
            CatalogTelegramSyncState.verificationUnavailable,
        packageId:
            journal.packageId,
        detail:
            error.toString(),
      );
    }
  }

  CatalogTelegramStatus _mapJournal(
    TelegramStorageUploadJournal? journal,
  ) {
    if (journal == null) {
      return const CatalogTelegramStatus.notUploaded();
    }

    if (verificationService
        .isRemoteMissingJournal(
      journal,
    )) {
      return CatalogTelegramStatus(
        state:
            CatalogTelegramSyncState.remoteMissing,
        packageId:
            journal.packageId,
        detail:
            journal.lastError,
      );
    }

    switch (journal.status) {
      case TelegramStorageUploadStatus.preparing:
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.preparing,
          packageId:
              journal.packageId,
        );

      case TelegramStorageUploadStatus.uploading:
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.uploading,
          packageId:
              journal.packageId,
        );

      case TelegramStorageUploadStatus.failed:
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.failed,
          packageId:
              journal.packageId,
          detail:
              journal.lastError,
        );

      case TelegramStorageUploadStatus.stored:
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.uploaded,
          packageId:
              journal.packageId,
        );

      case TelegramStorageUploadStatus.removing:
        return CatalogTelegramStatus(
          state:
              CatalogTelegramSyncState.removing,
          packageId:
              journal.packageId,
        );
    }
  }
}
