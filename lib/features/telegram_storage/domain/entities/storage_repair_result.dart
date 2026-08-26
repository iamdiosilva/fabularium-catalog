class StorageRepairResult {
  final String packageId;
  final bool alreadyHealthy;
  final int galleryMessagesRemoved;
  final int fileMessagesRemoved;
  final int fileGroupsReset;
  final bool galleryReset;
  final bool manifestReset;

  const StorageRepairResult({
    required this.packageId,
    required this.alreadyHealthy,
    required this.galleryMessagesRemoved,
    required this.fileMessagesRemoved,
    required this.fileGroupsReset,
    required this.galleryReset,
    required this.manifestReset,
  });

  int get remoteMessagesRemoved =>
      galleryMessagesRemoved + fileMessagesRemoved;

  bool get changed =>
      galleryReset || fileGroupsReset > 0 || manifestReset;
}
