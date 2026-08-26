enum CatalogTelegramSyncState {
  checking,
  notUploaded,
  preparing,
  uploading,
  failed,
  uploaded,
  remoteMissing,
  removing,
  verificationUnavailable,
}

class CatalogTelegramStatus {
  final CatalogTelegramSyncState state;
  final String? packageId;
  final String? detail;
  final bool remoteVerified;

  const CatalogTelegramStatus({
    required this.state,
    this.packageId,
    this.detail,
    this.remoteVerified = false,
  });

  const CatalogTelegramStatus.notUploaded()
      : state = CatalogTelegramSyncState.notUploaded,
        packageId = null,
        detail = null,
        remoteVerified = false;

  const CatalogTelegramStatus.checking({this.packageId})
      : state = CatalogTelegramSyncState.checking,
        detail = null,
        remoteVerified = false;

  String get label {
    switch (state) {
      case CatalogTelegramSyncState.checking:
        return 'Checking Telegram';
      case CatalogTelegramSyncState.notUploaded:
        return 'Not uploaded';
      case CatalogTelegramSyncState.preparing:
        return 'Preparing';
      case CatalogTelegramSyncState.uploading:
        return 'Uploading';
      case CatalogTelegramSyncState.failed:
        return 'Upload failed';
      case CatalogTelegramSyncState.uploaded:
        return remoteVerified ? 'Uploaded · verified' : 'Uploaded';
      case CatalogTelegramSyncState.remoteMissing:
        return 'Telegram incomplete';
      case CatalogTelegramSyncState.removing:
        return 'Removing';
      case CatalogTelegramSyncState.verificationUnavailable:
        return 'Uploaded · unchecked';
    }
  }

  bool get isUploaded =>
      state == CatalogTelegramSyncState.uploaded ||
      state == CatalogTelegramSyncState.verificationUnavailable;

  bool get isBusy =>
      state == CatalogTelegramSyncState.preparing ||
      state == CatalogTelegramSyncState.uploading ||
      state == CatalogTelegramSyncState.removing ||
      state == CatalogTelegramSyncState.checking;
}
