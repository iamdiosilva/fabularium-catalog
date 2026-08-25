import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/telegram_media.dart';

class TelegramFileService {
  TelegramFileService._();

  static final TelegramFileService instance =
      TelegramFileService._();

  File downloadFile(
    TelegramMedia media, {
    required String groupTitle,
  }) {
    return File(
      p.join(
        _downloadDirectoryPath(
          groupTitle,
        ),
        sanitizeFileName(
          media.fileName,
        ),
      ),
    );
  }

  File previewFile(
    TelegramMedia media,
  ) {
    return File(
      p.join(
        _cacheDirectoryPath(),
        '${sanitizeFileName(media.cacheKey)}.jpg',
      ),
    );
  }

  String? getDownloadedMediaPath(
    TelegramMedia media, {
    required String groupTitle,
  }) {
    try {
      final file =
          downloadFile(
        media,
        groupTitle:
            groupTitle,
      );

      if (!file.existsSync()) {
        return null;
      }

      if (media.size > 0 &&
          file.lengthSync() !=
              media.size) {
        return null;
      }

      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> showFileInExplorer(
    String filePath,
  ) async {
    final file =
        File(
      filePath,
    );

    if (!await file.exists()) {
      return;
    }

    if (Platform.isWindows) {
      await Process.run(
        'explorer.exe',
        [
          '/select,',
          file.path,
        ],
      );

      return;
    }

    await Process.run(
      'xdg-open',
      [
        file.parent.path,
      ],
    );
  }

  String sanitizeFileName(
    String value,
  ) {
    var result =
        value.replaceAll(
      RegExp(
        r'[<>:"/\\|?*\x00-\x1F]',
      ),
      '_',
    );

    result =
        result.trim();

    while (result.endsWith(
          '.',
        ) ||
        result.endsWith(
          ' ',
        )) {
      result =
          result.substring(
        0,
        result.length - 1,
      );
    }

    return result.isEmpty
        ? 'telegram_file'
        : result;
  }

  String _downloadDirectoryPath(
    String groupTitle,
  ) {
    final userProfile =
        Platform.environment[
            'USERPROFILE'];

    final basePath =
        userProfile != null &&
                userProfile.isNotEmpty
            ? p.join(
                userProfile,
                'Downloads',
              )
            : Directory.current.path;

    return p.join(
      basePath,
      'Fabularium',
      'Telegram',
      sanitizeFileName(
        groupTitle,
      ),
    );
  }

  String _cacheDirectoryPath() {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData != null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    return p.join(
      basePath,
      'Fabularium',
      'Telegram',
      'cache',
    );
  }
}
