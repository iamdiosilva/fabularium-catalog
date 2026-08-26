import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/telegram_media.dart';

class TelegramFileService {
  TelegramFileService._();
  static final TelegramFileService instance = TelegramFileService._();

  static const int previewCacheMaxBytes = 500 * 1024 * 1024;
  static const Duration previewCacheMaxAge = Duration(days: 30);
  static const Duration _abandonedPartMaxAge = Duration(days: 1);
  Future<void>? _previewCleanupFuture;

  File downloadFile(TelegramMedia media, {required String groupTitle}) => File(
        p.join(
          _downloadDirectoryPath(groupTitle),
          sanitizeFileName(media.fileName),
        ),
      );

  File previewFile(TelegramMedia media) => File(
        p.join(_cacheDirectoryPath(), '${sanitizeFileName(media.cacheKey)}.jpg'),
      );

  Future<void> cleanupPreviewCache({
    int maxBytes = previewCacheMaxBytes,
    Duration maxAge = previewCacheMaxAge,
    Set<String> protectedPaths = const <String>{},
  }) {
    final existing = _previewCleanupFuture;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _cleanupPreviewCacheInternal(
      maxBytes: maxBytes,
      maxAge: maxAge,
      protectedPaths: protectedPaths,
    ).whenComplete(() {
      if (identical(_previewCleanupFuture, future)) _previewCleanupFuture = null;
    });
    _previewCleanupFuture = future;
    return future;
  }

  Future<void> _cleanupPreviewCacheInternal({
    required int maxBytes,
    required Duration maxAge,
    required Set<String> protectedPaths,
  }) async {
    try {
      final directory = Directory(_cacheDirectoryPath());
      if (!await directory.exists()) return;
      final protected = protectedPaths.map(_pathKey).toSet();
      final now = DateTime.now();
      final expirationLimit = now.subtract(maxAge);
      final abandonedPartLimit = now.subtract(_abandonedPartMaxAge);
      final entries = <_PreviewCacheEntry>[];

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final file = entity;
        final pathKey = _pathKey(file.path);
        final isProtected = protected.contains(pathKey);
        FileStat stat;
        try {
          stat = await file.stat();
        } catch (_) {
          continue;
        }
        if (file.path.toLowerCase().endsWith('.part')) {
          if (!isProtected && stat.modified.isBefore(abandonedPartLimit)) {
            try {
              await file.delete();
            } catch (_) {}
          }
          continue;
        }
        if (!isProtected && stat.modified.isBefore(expirationLimit)) {
          try {
            await file.delete();
            continue;
          } catch (_) {}
        }
        entries.add(_PreviewCacheEntry(
          file: file,
          size: stat.size,
          modified: stat.modified,
          protected: isProtected,
        ));
      }

      if (maxBytes <= 0 || entries.isEmpty) return;
      var totalBytes = entries.fold<int>(0, (sum, entry) => sum + entry.size);
      if (totalBytes <= maxBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (totalBytes <= maxBytes) break;
        if (entry.protected) continue;
        try {
          if (await entry.file.exists()) {
            await entry.file.delete();
            totalBytes -= entry.size;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  String _pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String? getDownloadedMediaPath(
    TelegramMedia media, {
    required String groupTitle,
  }) {
    try {
      final file = downloadFile(media, groupTitle: groupTitle);
      if (!file.existsSync()) return null;
      if (media.size > 0 && file.lengthSync() != media.size) return null;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> showFileInExplorer(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>['/select,', file.path]);
      return;
    }
    await Process.run('xdg-open', <String>[file.parent.path]);
  }

  String sanitizeFileName(String value) {
    var result = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    while (result.endsWith('.') || result.endsWith(' ')) {
      result = result.substring(0, result.length - 1);
    }
    return result.isEmpty ? 'telegram_file' : result;
  }

  String _downloadDirectoryPath(String groupTitle) {
    final userProfile = Platform.environment['USERPROFILE'];
    final basePath = userProfile != null && userProfile.isNotEmpty
        ? p.join(userProfile, 'Downloads')
        : Directory.current.path;
    return p.join(
      basePath,
      'Fabularium',
      'Telegram',
      sanitizeFileName(groupTitle),
    );
  }

  String _cacheDirectoryPath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final basePath = localAppData != null && localAppData.isNotEmpty
        ? localAppData
        : Directory.systemTemp.path;
    return p.join(basePath, 'Fabularium', 'Telegram', 'cache');
  }
}

class _PreviewCacheEntry {
  final File file;
  final int size;
  final DateTime modified;
  final bool protected;

  const _PreviewCacheEntry({
    required this.file,
    required this.size,
    required this.modified,
    required this.protected,
  });
}
