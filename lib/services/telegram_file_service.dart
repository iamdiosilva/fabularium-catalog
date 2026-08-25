import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/telegram_media.dart';

class TelegramFileService {
  TelegramFileService._();

  static final TelegramFileService instance =
      TelegramFileService._();

  static const int previewCacheMaxBytes =
      500 * 1024 * 1024;

  static const Duration previewCacheMaxAge =
      Duration(
    days: 30,
  );

  static const Duration _abandonedPartMaxAge =
      Duration(
    days: 1,
  );

  Future<void>? _previewCleanupFuture;

  // ============================================================
  // DOWNLOAD FILE
  // ============================================================

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

  // ============================================================
  // PREVIEW FILE
  // ============================================================

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

  // ============================================================
  // PREVIEW CACHE MAINTENANCE
  // ============================================================

  Future<void> cleanupPreviewCache({
    int maxBytes = previewCacheMaxBytes,
    Duration maxAge = previewCacheMaxAge,
    Set<String> protectedPaths =
        const <String>{},
  }) {
    /*
     * Evita duas varreduras físicas do cache
     * acontecendo ao mesmo tempo.
     */
    final existing =
        _previewCleanupFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void> future;

    future = _cleanupPreviewCacheInternal(
      maxBytes:
          maxBytes,
      maxAge:
          maxAge,
      protectedPaths:
          protectedPaths,
    ).whenComplete(
      () {
        if (identical(
          _previewCleanupFuture,
          future,
        )) {
          _previewCleanupFuture =
              null;
        }
      },
    );

    _previewCleanupFuture =
        future;

    return future;
  }

  Future<void> _cleanupPreviewCacheInternal({
    required int maxBytes,
    required Duration maxAge,
    required Set<String> protectedPaths,
  }) async {
    try {
      final directory =
          Directory(
        _cacheDirectoryPath(),
      );

      if (!await directory.exists()) {
        return;
      }

      final protected =
          protectedPaths
              .map(
                _pathKey,
              )
              .toSet();

      final now =
          DateTime.now();

      final expirationLimit =
          now.subtract(
        maxAge,
      );

      final abandonedPartLimit =
          now.subtract(
        _abandonedPartMaxAge,
      );

      final entries =
          <_PreviewCacheEntry>[];

      /*
       * Fazemos a leitura do diretório de forma
       * assíncrona para não bloquear a UI.
       */
      await for (final entity
          in directory.list(
        followLinks:
            false,
      )) {
        if (entity is! File) {
          continue;
        }

        final file =
            entity;

        final pathKey =
            _pathKey(
          file.path,
        );

        final isProtected =
            protected.contains(
          pathKey,
        );

        FileStat stat;

        try {
          stat =
              await file.stat();
        } catch (_) {
          continue;
        }

        /*
         * Arquivos .part são temporários usados
         * pelo downloader.
         *
         * Nunca apagamos um .part recente porque
         * ele pode estar sendo escrito neste exato
         * momento.
         *
         * Porém, se ficou abandonado por mais de
         * 24 horas, pode ser removido.
         */
        if (file.path
            .toLowerCase()
            .endsWith(
              '.part',
            )) {
          if (!isProtected &&
              stat.modified.isBefore(
                abandonedPartLimit,
              )) {
            try {
              await file.delete();
            } catch (_) {}
          }

          continue;
        }

        /*
         * Previews que estão atualmente no cache
         * em memória da aplicação ficam protegidas
         * desta rodada de manutenção.
         */
        if (!isProtected &&
            stat.modified.isBefore(
              expirationLimit,
            )) {
          try {
            await file.delete();

            continue;
          } catch (_) {
            /*
             * Se não foi possível excluir,
             * mantemos o arquivo no cálculo
             * de tamanho abaixo.
             */
          }
        }

        entries.add(
          _PreviewCacheEntry(
            file:
                file,
            size:
                stat.size,
            modified:
                stat.modified,
            protected:
                isProtected,
          ),
        );
      }

      if (maxBytes <= 0 ||
          entries.isEmpty) {
        return;
      }

      int totalBytes =
          0;

      for (final entry
          in entries) {
        totalBytes +=
            entry.size;
      }

      if (totalBytes <=
          maxBytes) {
        return;
      }

      /*
       * LRU aproximado baseado na data de
       * modificação do arquivo.
       *
       * Os arquivos mais antigos são os
       * primeiros candidatos à remoção.
       */
      entries.sort(
        (
          a,
          b,
        ) =>
            a.modified.compareTo(
          b.modified,
        ),
      );

      for (final entry
          in entries) {
        if (totalBytes <=
            maxBytes) {
          break;
        }

        if (entry.protected) {
          continue;
        }

        try {
          if (await entry.file.exists()) {
            await entry.file.delete();

            totalBytes -=
                entry.size;
          }
        } catch (_) {
          /*
           * Cache é best effort.
           *
           * Uma falha ao excluir um arquivo não
           * deve impedir o restante da aplicação.
           */
        }
      }
    } catch (_) {
      /*
       * Manutenção de cache nunca deve derrubar
       * navegação, previews ou downloads.
       */
    }
  }

  String _pathKey(
    String path,
  ) {
    final normalized =
        p.normalize(
      p.absolute(
        path,
      ),
    );

    /*
     * Windows não diferencia maiúsculas de
     * minúsculas em caminhos.
     */
    if (Platform.isWindows) {
      return normalized
          .toLowerCase();
    }

    return normalized;
  }

  // ============================================================
  // DOWNLOADED MEDIA
  // ============================================================

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

  // ============================================================
  // EXPLORER
  // ============================================================

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

  // ============================================================
  // FILE NAME
  // ============================================================

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

  // ============================================================
  // DOWNLOAD DIRECTORY
  // ============================================================

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

  // ============================================================
  // CACHE DIRECTORY
  // ============================================================

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