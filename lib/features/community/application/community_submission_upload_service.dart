import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../config/community_worker_config.dart';
import '../../../../services/supabase_service.dart';

typedef CommunityUploadProgressCallback =
    void Function(
  double progress,
  int sentBytes,
  int totalBytes,
);

class CommunitySubmissionUploadService {
  CommunitySubmissionUploadService._();

  static final CommunitySubmissionUploadService
      instance =
      CommunitySubmissionUploadService._();

  Future<void> uploadArchive({
    required String submissionId,
    required String filePath,
    CommunityUploadProgressCallback? onProgress,
  }) async {
    final file =
        File(filePath);

    if (!await file.exists()) {
      throw const CommunitySubmissionUploadException(
        'The selected archive no longer exists.',
      );
    }

    final totalBytes =
        await file.length();

    if (totalBytes <= 0) {
      throw const CommunitySubmissionUploadException(
        'The selected archive is empty.',
      );
    }

    final session =
        SupabaseService.instance
            .client
            ?.auth
            .currentSession;

    if (session == null) {
      throw const CommunitySubmissionUploadException(
        'Sign in to Fabularium before uploading.',
      );
    }

    final client =
        HttpClient()
          ..connectionTimeout =
              const Duration(
            seconds: 20,
          );

    try {
      final request =
          await client.postUrl(
        CommunityWorkerConfig.uploadUri,
      );

      request.bufferOutput = false;
      request.contentLength =
          totalBytes;

      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.accessToken}',
      );

      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/octet-stream',
      );

      request.headers.set(
        'X-Fabularium-Submission-Id',
        submissionId,
      );

      request.headers.set(
        'X-Fabularium-File-Name',
        Uri.encodeComponent(
          p.basename(file.path),
        ),
      );

      var sentBytes = 0;

      await for (final chunk
          in file.openRead()) {
        request.add(
          chunk,
        );

        sentBytes +=
            chunk.length;

        onProgress?.call(
          sentBytes /
              totalBytes,
          sentBytes,
          totalBytes,
        );
      }

      final response =
          await request.close();

      final body =
          await utf8.decoder
              .bind(response)
              .join();

      if (response.statusCode <
              200 ||
          response.statusCode >=
              300) {
        var message =
            body.trim();

        try {
          final decoded =
              jsonDecode(body);

          if (decoded is Map &&
              decoded['error'] !=
                  null) {
            message =
                decoded['error']
                    .toString();
          }
        } catch (_) {}

        throw CommunitySubmissionUploadException(
          message.isEmpty
              ? 'Worker returned HTTP ${response.statusCode}.'
              : message,
        );
      }

      onProgress?.call(
        1,
        totalBytes,
        totalBytes,
      );
    } on SocketException catch (error) {
      throw CommunitySubmissionUploadException(
        'Could not connect to the Fabularium Worker: ${error.message}',
      );
    } finally {
      client.close(
        force: true,
      );
    }
  }
}

class CommunitySubmissionUploadException
    implements Exception {
  final String message;

  const CommunitySubmissionUploadException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
