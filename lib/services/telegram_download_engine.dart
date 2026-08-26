/// Kept as a compatibility boundary for the previous download architecture.
/// Download orchestration now lives behind TelegramDownloadWorker.
class TelegramDownloadEngine {
  TelegramDownloadEngine._();
  static final TelegramDownloadEngine instance = TelegramDownloadEngine._();
}
