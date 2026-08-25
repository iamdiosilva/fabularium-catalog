import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;

import '../models/telegram_media.dart';
import 'telegram_client.dart';

class TelegramDownloadEngine {
  TelegramDownloadEngine._();

  static final TelegramDownloadEngine instance =
      TelegramDownloadEngine._();

  final TelegramClient _telegramClient =
      TelegramClient.instance;

  static const int _chunkSize =
      1024 * 1024;

  static const int _previewChunkSize =
      512 * 1024;

  static const int _connectionCount =
      4;

  static const int _maxInFlight =
      8;

  // ============================================================
  // LARGE FILE DOWNLOAD
  // ============================================================

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    final directory =
        await _getDownloadDirectory(
      groupTitle,
    );

    final destination =
        File(
      p.join(
        directory.path,
        _sanitizeFileName(
          media.fileName,
        ),
      ),
    );

    return _downloadLargeLocation(
      initialDcId:
          media.dcId,
      location:
          media.location,
      destination:
          destination,
      expectedSize:
          media.size,
      onProgress:
          onProgress,
    );
  }

  // ============================================================
  // PREVIEW DOWNLOAD
  // ============================================================

  Future<String> downloadPreview(
    TelegramMedia media,
  ) async {
    final location =
        media.previewLocation;

    if (location == null) {
      throw StateError(
        'Preview is not available.',
      );
    }

    final directory =
        await _getCacheDirectory();

    final destination =
        File(
      p.join(
        directory.path,
        '${_sanitizeFileName(media.cacheKey)}.jpg',
      ),
    );

    return _downloadSmallLocation(
      initialDcId:
          media.dcId,
      location:
          location,
      destination:
          destination,
      expectedSize:
          media.previewSize ??
              0,
    );
  }

  // ============================================================
  // HIGH PERFORMANCE FILE
  // ============================================================

  Future<String> _downloadLargeLocation({
    required int initialDcId,
    required t.InputFileLocationBase
        location,
    required File destination,
    required int expectedSize,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    await destination.parent.create(
      recursive:
          true,
    );

    if (await destination.exists()) {
      final size =
          await destination.length();

      if (expectedSize <= 0 ||
          size ==
              expectedSize) {
        onProgress?.call(
          size,
          expectedSize,
        );

        return destination.path;
      }
    }

    final tempFile =
        File(
      '${destination.path}.part',
    );

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await _telegramClient
        .warmDownloadPool(
      initialDcId,
      size:
          _connectionCount,
    );

    final randomAccessFile =
        await tempFile.open(
      mode:
          FileMode.write,
    );

    if (expectedSize >
        0) {
      await randomAccessFile
          .truncate(
        expectedSize,
      );
    }

    final writer =
        _RandomAccessWriter(
      randomAccessFile,
    );

    final inFlight =
        <int,
            Future<_TelegramDownloadChunk>>{};

    int nextOffset =
        0;

    int nextChunkIndex =
        0;

    int receivedBytes =
        0;

    int? discoveredEnd;

    void fillWindow() {
      while (inFlight.length <
          _maxInFlight) {
        if (expectedSize >
                0 &&
            nextOffset >=
                expectedSize) {
          break;
        }

        if (discoveredEnd !=
                null &&
            nextOffset >=
                discoveredEnd!) {
          break;
        }

        final offset =
            nextOffset;

        final slot =
            nextChunkIndex %
                _connectionCount;

        inFlight[
                offset] =
            _downloadChunk(
          initialDcId:
              initialDcId,
          slot:
              slot,
          location:
              location,
          offset:
              offset,
          limit:
              _chunkSize,
        );

        nextOffset +=
            _chunkSize;

        nextChunkIndex++;
      }
    }

    try {
      fillWindow();

      while (inFlight.isNotEmpty) {
        final chunk =
            await Future.any(
          inFlight.values,
        );

        inFlight.remove(
          chunk.offset,
        );

        if (chunk.bytes.length <
            _chunkSize) {
          final end =
              chunk.offset +
                  chunk.bytes.length;

          if (discoveredEnd ==
                  null ||
              end <
                  discoveredEnd!) {
            discoveredEnd =
                end;
          }
        }

        if (discoveredEnd !=
                null &&
            chunk.offset >=
                discoveredEnd!) {
          fillWindow();

          continue;
        }

        if (chunk.bytes.isNotEmpty) {
          await writer.writeAt(
            chunk.offset,
            chunk.bytes,
          );

          receivedBytes +=
              chunk.bytes.length;

          onProgress?.call(
            receivedBytes,
            expectedSize,
          );
        }

        fillWindow();
      }

      await writer.flush();

      if (expectedSize >
              0 &&
          receivedBytes <
              expectedSize) {
        throw Exception(
          'Incomplete download. '
          'Expected: $expectedSize bytes. '
          'Received: $receivedBytes bytes.',
        );
      }
    } catch (_) {
      try {
        await writer.close();
      } catch (_) {}

      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      rethrow;
    }

    await writer.close();

    if (await destination.exists()) {
      await destination.delete();
    }

    final completed =
        await tempFile.rename(
      destination.path,
    );

    final finalSize =
        expectedSize >
                0
            ? expectedSize
            : await completed.length();

    onProgress?.call(
      finalSize,
      finalSize,
    );

    return completed.path;
  }

  // ============================================================
  // SMALL FILE / PREVIEW
  // ============================================================

  Future<String> _downloadSmallLocation({
    required int initialDcId,
    required t.InputFileLocationBase
        location,
    required File destination,
    required int expectedSize,
  }) async {
    await destination.parent.create(
      recursive:
          true,
    );

    if (await destination.exists()) {
      if (expectedSize <=
          0) {
        return destination.path;
      }

      final existingSize =
          await destination.length();

      if (existingSize ==
          expectedSize) {
        return destination.path;
      }
    }

    final temp =
        File(
      '${destination.path}.part',
    );

    if (await temp.exists()) {
      await temp.delete();
    }

    /*
     * Preview worker uses only one dedicated
     * media session.
     *
     * This prevents a thumbnail storm.
     */
    int dcId =
        initialDcId;

    var client =
        await _telegramClient
            .getDownloadClientForDataCenter(
      dcId,
      0,
    );

    int offset =
        0;

    int migrations =
        0;

    final output =
        await temp.open(
      mode:
          FileMode.write,
    );

    try {
      while (true) {
        final response =
            await client.upload
                .getFile(
          precise:
              false,
          cdnSupported:
              false,
          location:
              location,
          offset:
              offset,
          limit:
              _previewChunkSize,
        );

        if (response.error != null) {
          final errorMessage =
              response
                  .error!
                  .errorMessage;

          final migrateDc =
              _extractMigrationDc(
            errorMessage,
          );

          if (migrateDc != null) {
            migrations++;

            if (migrations >
                3) {
              throw Exception(
                'Too many Telegram DC migrations.',
              );
            }

            dcId =
                migrateDc;

            client =
                await _telegramClient
                    .getDownloadClientForDataCenter(
              dcId,
              0,
            );

            continue;
          }

          throw Exception(
            errorMessage,
          );
        }

        final dynamic result =
            response.result;

        if (result == null) {
          throw Exception(
            'Telegram returned an empty preview response.',
          );
        }

        final bytes =
            _readBytes(
          result,
        );

        if (bytes.isEmpty) {
          break;
        }

        await output.writeFrom(
          bytes,
        );

        offset +=
            bytes.length;

        if (expectedSize >
                0 &&
            offset >=
                expectedSize) {
          break;
        }

        if (bytes.length <
            _previewChunkSize) {
          break;
        }
      }
    } finally {
      await output.close();
    }

    if (expectedSize >
        0) {
      final downloaded =
          await temp.length();

      if (downloaded <
          expectedSize) {
        try {
          await temp.delete();
        } catch (_) {}

        throw Exception(
          'Incomplete Telegram preview.',
        );
      }
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    return temp.rename(
      destination.path,
    ).then(
      (file) =>
          file.path,
    );
  }

  // ============================================================
  // CHUNK
  // ============================================================

  Future<_TelegramDownloadChunk>
      _downloadChunk({
    required int initialDcId,
    required int slot,
    required t.InputFileLocationBase
        location,
    required int offset,
    required int limit,
  }) async {
    int dcId =
        initialDcId;

    int migrationCount =
        0;

    while (true) {
      final client =
          await _telegramClient
              .getDownloadClientForDataCenter(
        dcId,
        slot,
      );

      final response =
          await client.upload
              .getFile(
        precise:
            false,
        cdnSupported:
            false,
        location:
            location,
        offset:
            offset,
        limit:
            limit,
      );

      final error =
          response.error;

      if (error != null) {
        final migrateDc =
            _extractMigrationDc(
          error.errorMessage,
        );

        if (migrateDc !=
            null) {
          migrationCount++;

          if (migrationCount >
              3) {
            throw Exception(
              'Too many Telegram DC migrations.',
            );
          }

          dcId =
              migrateDc;

          continue;
        }

        throw Exception(
          error.errorMessage,
        );
      }

      final dynamic result =
          response.result;

      if (result == null) {
        throw Exception(
          'Telegram returned an empty file response.',
        );
      }

      return _TelegramDownloadChunk(
        offset:
            offset,
        bytes:
            _readBytes(
          result,
        ),
        dcId:
            dcId,
      );
    }
  }

  Uint8List _readBytes(
    dynamic result,
  ) {
    try {
      final dynamic rawBytes =
          result.bytes;

      if (rawBytes is Uint8List) {
        return rawBytes;
      }

      return Uint8List.fromList(
        List<int>.from(
          rawBytes as List,
        ),
      );
    } catch (_) {
      throw Exception(
        'Unsupported Telegram file response.',
      );
    }
  }

  int? _extractMigrationDc(
    String message,
  ) {
    const prefixes =
        <String>[
      'FILE_MIGRATE_',
      'NETWORK_MIGRATE_',
    ];

    for (final prefix
        in prefixes) {
      if (!message.startsWith(
        prefix,
      )) {
        continue;
      }

      return int.tryParse(
        message
            .substring(
          prefix.length,
        )
            .trim(),
      );
    }

    return null;
  }

  // ============================================================
  // DIRECTORIES
  // ============================================================

  Future<Directory>
      _getDownloadDirectory(
    String groupTitle,
  ) async {
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

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        _sanitizeFileName(
          groupTitle,
        ),
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  Future<Directory>
      _getCacheDirectory() async {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData != null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        'cache',
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  String _sanitizeFileName(
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
}

class _TelegramDownloadChunk {
  final int offset;

  final Uint8List bytes;

  final int dcId;

  const _TelegramDownloadChunk({
    required this.offset,
    required this.bytes,
    required this.dcId,
  });
}

class _RandomAccessWriter {
  final RandomAccessFile _file;

  Future<void> _tail =
      Future<void>.value();

  _RandomAccessWriter(
    this._file,
  );

  Future<void> writeAt(
    int offset,
    Uint8List bytes,
  ) {
    final operation =
        _tail.then(
      (_) async {
        await _file.setPosition(
          offset,
        );

        await _file.writeFrom(
          bytes,
        );
      },
    );

    _tail =
        operation;

    return operation;
  }

  Future<void> flush() async {
    await _tail;

    await _file.flush();
  }

  Future<void> close() async {
    try {
      await _tail;
    } finally {
      await _file.close();
    }
  }
}