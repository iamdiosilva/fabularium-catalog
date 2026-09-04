class CommunityWorkerConfig {
  CommunityWorkerConfig._();

  static const String baseUrl =
      String.fromEnvironment(
    'FABULARIUM_WORKER_URL',
    defaultValue:
        'http://127.0.0.1:8787',
  );

  static Uri get uploadUri {
    final uri = Uri.parse(
      '$baseUrl/v1/submissions/upload',
    );

    if (!uri.hasScheme ||
        uri.host.trim().isEmpty) {
      throw const CommunityWorkerConfigException(
        'FABULARIUM_WORKER_URL is invalid.',
      );
    }

    final isLoopback =
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost' ||
        uri.host == '::1';

    if (uri.scheme != 'https' &&
        !isLoopback) {
      throw const CommunityWorkerConfigException(
        'Remote Fabularium Worker connections must use HTTPS.',
      );
    }

    return uri;
  }
}

class CommunityWorkerConfigException
    implements Exception {
  final String message;

  const CommunityWorkerConfigException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
