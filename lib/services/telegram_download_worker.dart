import 'dart:io';
import 'package:t/t.dart' as t;

import '../models/telegram_media.dart';
import 'telegram_client.dart';
import 'telegram_file_service.dart';

class TelegramDownloadWorker {
  TelegramDownloadWorker._();
  static final TelegramDownloadWorker instance = TelegramDownloadWorker._();

  final TelegramClient _telegram = TelegramClient.instance;
  final TelegramFileService _files = TelegramFileService.instance;
  Future<void> Function(String message)? _sessionInvalidHandler;
  bool _interactive = false;
  int _generation = 0;

  void setSessionInvalidHandler(Future<void> Function(String message)? value) {
    _sessionInvalidHandler = value;
  }

  void setInteractiveMode(bool value) => _interactive = value;

  Future<void> resetSession() async {
    _generation++;
    await _telegram.disconnect();
  }

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    required void Function(int received, int total) onProgress,
  }) async {
    final target = _files.downloadFile(media, groupTitle: groupTitle);
    await target.parent.create(recursive: true);
    if (await target.exists() &&
        (media.size <= 0 || await target.length() == media.size)) {
      onProgress(media.size, media.size);
      return target.path;
    }
    return _download(
      media: media,
      location: media.location,
      expectedSize: media.size,
      target: target,
      onProgress: onProgress,
    );
  }

  Future<String?> downloadPreview(TelegramMedia media) async {
    final location = media.previewLocation;
    if (location == null) return null;
    final target = _files.previewFile(media);
    await target.parent.create(recursive: true);
    if (await target.exists()) return target.path;
    return _download(
      media: media,
      location: location,
      expectedSize: media.previewSize ?? 0,
      target: target,
      onProgress: (received, total) {},
    );
  }

  Future<String> _download({
    required TelegramMedia media,
    required t.InputFileLocationBase location,
    required int expectedSize,
    required File target,
    required void Function(int received, int total) onProgress,
  }) async {
    final generation = _generation;
    final part = File('${target.path}.part');
    RandomAccessFile? output;
    try {
      if (await part.exists()) await part.delete();
      output = await part.open(mode: FileMode.write);
      await _telegram.connect();
      final dataClient = await _telegram.getClientForDataCenter(media.dcId);
      const chunkSize = 512 * 1024;
      int offset = 0;
      while (true) {
        if (generation != _generation) {
          throw const TelegramDownloadException('Download session was reset.');
        }
        final response = await dataClient.invoke(
          t.UploadGetFile(
            precise: false,
            cdnSupported: false,
            location: location,
            offset: offset,
            limit: chunkSize,
          ),
        ).timeout(const Duration(seconds: 60));
        if (response.error != null) {
          final message = response.error!.errorMessage;
          if (_isSessionError(message)) await _sessionInvalidHandler?.call(message);
          throw TelegramDownloadException(message);
        }
        final dynamic result = response.result;
        if (result == null) break;
        List<int> bytes = const <int>[];
        try { bytes = List<int>.from(result.bytes as List); } catch (_) {}
        if (bytes.isEmpty) break;
        await output.writeFrom(bytes);
        offset += bytes.length;
        onProgress(offset, expectedSize > 0 ? expectedSize : offset);
        if (bytes.length < chunkSize || (expectedSize > 0 && offset >= expectedSize)) break;
        if (_interactive) await Future<void>.delayed(Duration.zero);
      }
      await output.flush();
      await output.close();
      output = null;
      if (expectedSize > 0 && await part.length() != expectedSize) {
        throw TelegramDownloadException(
          'Downloaded size mismatch: ${await part.length()}/$expectedSize bytes.',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return target.path;
    } catch (e) {
      try { await output?.close(); } catch (_) {}
      try { if (await part.exists()) await part.delete(); } catch (_) {}
      rethrow;
    } finally {
      // Auxiliary clients are pooled by TelegramClient and reused by the queue.
    }
  }

  bool _isSessionError(String value) =>
      value.contains('AUTH_KEY_UNREGISTERED') ||
      value.contains('AUTH_KEY_INVALID') ||
      value.contains('SESSION_REVOKED') ||
      value.contains('SESSION_EXPIRED');
}

class TelegramDownloadException implements Exception {
  final String message;
  const TelegramDownloadException(this.message);
  @override
  String toString() => message;
}
