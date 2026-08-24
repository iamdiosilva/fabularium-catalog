import 'telegram_media.dart';

enum DownloadTaskStatus {
  queued,
  downloading,
  completed,
  failed,
}

class DownloadTask {
  final String id;

  final TelegramMedia media;

  final String groupTitle;

  final DateTime createdAt;

  DownloadTaskStatus status;

  int receivedBytes;

  int totalBytes;

  String? filePath;

  String? errorMessage;

  DateTime? startedAt;

  DateTime? completedAt;

  double bytesPerSecond;

  Duration? estimatedRemaining;

  DownloadTask({
    required this.id,
    required this.media,
    required this.groupTitle,
    required this.createdAt,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    this.filePath,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    this.bytesPerSecond = 0,
    this.estimatedRemaining,
  });

  double? get progress {
    if (totalBytes <=
        0) {
      return null;
    }

    return (receivedBytes /
            totalBytes)
        .clamp(
      0.0,
      1.0,
    );
  }

  bool get isQueued =>
      status ==
      DownloadTaskStatus.queued;

  bool get isDownloading =>
      status ==
      DownloadTaskStatus.downloading;

  bool get isCompleted =>
      status ==
      DownloadTaskStatus.completed;

  bool get isFailed =>
      status ==
      DownloadTaskStatus.failed;

  bool get isFinished =>
      isCompleted ||
      isFailed;
}