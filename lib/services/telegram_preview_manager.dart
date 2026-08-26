import 'dart:io';

import '../models/telegram_media.dart';
import 'telegram_download_worker.dart';
import 'telegram_file_service.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();
  static final TelegramPreviewManager instance = TelegramPreviewManager._();

  final TelegramFileService _files = TelegramFileService.instance;
  final Map<String, File> _memory = <String, File>{};
  int _generation = 0;

  void cancelPending() => _generation++;
  void clearMemoryCache() => _memory.clear();

  Future<File?> getPreview(TelegramMedia media) async {
    final location = media.previewLocation;
    if (location == null) return null;
    final cached = _memory[media.cacheKey];
    if (cached != null && await cached.exists()) return cached;
    final target = _files.previewFile(media);
    if (await target.exists()) {
      _memory[media.cacheKey] = target;
      return target;
    }
    final generation = _generation;
    try {
      final path = await TelegramDownloadWorker.instance.downloadPreview(media);
      if (generation != _generation || path == null) return null;
      final file = File(path);
      _memory[media.cacheKey] = file;
      return file;
    } catch (_) {
      return null;
    }
  }
}
