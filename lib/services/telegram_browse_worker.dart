/// Compatibility lifecycle facade. Browsing screens own their short-lived
/// MTProto connection; this object centralizes session invalidation/reset.
class TelegramBrowseWorker {
  TelegramBrowseWorker._();
  static final TelegramBrowseWorker instance = TelegramBrowseWorker._();

  Future<void> Function(String message)? _sessionInvalidHandler;

  void setSessionInvalidHandler(Future<void> Function(String message)? value) {
    _sessionInvalidHandler = value;
  }

  Future<void> reportSessionInvalid(String message) async {
    await _sessionInvalidHandler?.call(message);
  }

  Future<void> reset({Object? reason, bool clearCache = true}) async {}
}
