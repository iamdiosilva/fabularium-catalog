import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(
  List<String> args,
) async {
  final config =
      await _WorkerConfig.load(
    args,
  );

  final server =
      await HttpServer.bind(
    config.host,
    config.port,
  );

  stdout.writeln(
    '[Fabularium Worker] Listening on '
    'http://${server.address.host}:${server.port}',
  );

  stdout.writeln(
    '[Fabularium Worker] Data directory: '
    '${config.dataDirectory.path}',
  );

  await for (final request
      in server) {
    unawaited(
      _handle(
        request,
        config,
      ),
    );
  }
}

void unawaited(
  Future<void> future,
) {}

Future<void> _handle(
  HttpRequest request,
  _WorkerConfig config,
) async {
  try {
    if (request.method ==
            'GET' &&
        request.uri.path ==
            '/health') {
      await _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'ok': true,
          'service':
              'fabularium-worker',
        },
      );
      return;
    }

    if (request.method ==
            'POST' &&
        request.uri.path ==
            '/v1/submissions/upload') {
      await _handleUpload(
        request,
        config,
      );
      return;
    }

    await _json(
      request.response,
      HttpStatus.notFound,
      <String, dynamic>{
        'error':
            'Not found.',
      },
    );
  } catch (error, stackTrace) {
    stderr.writeln(
      '[Fabularium Worker] $error',
    );
    stderr.writeln(
      stackTrace,
    );

    try {
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{
          'error':
              error.toString(),
        },
      );
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _handleUpload(
  HttpRequest request,
  _WorkerConfig config,
) async {
  final token =
      _bearerToken(
    request,
  );

  if (token == null) {
    await _json(
      request.response,
      HttpStatus.unauthorized,
      <String, dynamic>{
        'error':
            'Fabularium authentication is required.',
      },
    );
    return;
  }

  final submissionId =
      request.headers
          .value(
            'X-Fabularium-Submission-Id',
          )
          ?.trim();

  if (submissionId == null ||
      submissionId.isEmpty) {
    await _json(
      request.response,
      HttpStatus.badRequest,
      <String, dynamic>{
        'error':
            'Submission ID is required.',
      },
    );
    return;
  }

  final rawFileName =
      request.headers
          .value(
            'X-Fabularium-File-Name',
          )
          ?.trim();

  final fileName =
      _sanitizeFileName(
    rawFileName == null
        ? 'submission.bin'
        : Uri.decodeComponent(
            rawFileName,
          ),
  );

  final expectedBytes =
      request.contentLength;

  if (expectedBytes <= 0) {
    await _json(
      request.response,
      HttpStatus.lengthRequired,
      <String, dynamic>{
        'error':
            'Content-Length is required.',
      },
    );
    return;
  }

  const maxUploadBytes =
      50 * 1024 * 1024 * 1024;

  if (expectedBytes >
      maxUploadBytes) {
    await _json(
      request.response,
      HttpStatus.requestEntityTooLarge,
      <String, dynamic>{
        'error':
            'Archive exceeds the current 50 GB intake limit.',
      },
    );
    return;
  }

  final user =
      await _SupabaseGateway(
    config,
  ).validateUser(
    token,
  );

  if (user == null) {
    await _json(
      request.response,
      HttpStatus.unauthorized,
      <String, dynamic>{
        'error':
            'Invalid or expired Fabularium session.',
      },
    );
    return;
  }

  final gateway =
      _SupabaseGateway(
    config,
  );

  final submission =
      await gateway
          .loadOwnedSubmission(
    submissionId:
        submissionId,
    userId:
        user.id,
  );

  if (submission == null) {
    await _json(
      request.response,
      HttpStatus.notFound,
      <String, dynamic>{
        'error':
            'Submission not found.',
      },
    );
    return;
  }

  if (submission.status !=
          'uploading' &&
      submission.status !=
          'failed') {
    await _json(
      request.response,
      HttpStatus.conflict,
      <String, dynamic>{
        'error':
            'Submission cannot receive an archive in status '
            '${submission.status}.',
      },
    );
    return;
  }

  if (submission.archiveSize >
          0 &&
      submission.archiveSize !=
          expectedBytes) {
    await _json(
      request.response,
      HttpStatus.conflict,
      <String, dynamic>{
        'error':
            'Archive size does not match the submission.',
      },
    );
    return;
  }

  if (submission.archiveFileName !=
          null &&
      submission.archiveFileName!
          .isNotEmpty &&
      submission.archiveFileName !=
          fileName) {
    await _json(
      request.response,
      HttpStatus.conflict,
      <String, dynamic>{
        'error':
            'Archive file name does not match the submission.',
      },
    );
    return;
  }

  final uploadDirectory =
      Directory(
    p.join(
      config.dataDirectory.path,
      'uploads',
      submissionId,
    ),
  );

  await uploadDirectory.create(
    recursive: true,
  );

  final partialFile =
      File(
    p.join(
      uploadDirectory.path,
      '$fileName.part',
    ),
  );

  final finalFile =
      File(
    p.join(
      uploadDirectory.path,
      fileName,
    ),
  );

  try {
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    if (await finalFile.exists()) {
      await finalFile.delete();
    }

    await gateway.startUpload(
      submissionId:
          submissionId,
      workerId:
          config.workerId,
      fileName:
          fileName,
      expectedBytes:
          expectedBytes,
    );

    final output =
        await partialFile.open(
      mode:
          FileMode.write,
    );

    var receivedBytes =
        0;

    try {
      await for (final chunk
          in request) {
        receivedBytes +=
            chunk.length;

        if (receivedBytes >
            expectedBytes) {
          throw const _WorkerException(
            'Received more bytes than Content-Length.',
          );
        }

        await output.writeFrom(
          chunk,
        );
      }

      await output.flush();
    } finally {
      await output.close();
    }

    if (receivedBytes !=
        expectedBytes) {
      throw _WorkerException(
        'Upload ended early. Expected '
        '$expectedBytes bytes, received '
        '$receivedBytes.',
      );
    }

    await partialFile.rename(
      finalFile.path,
    );

    await gateway.completeUpload(
      submissionId:
          submissionId,
      fileName:
          fileName,
      receivedBytes:
          receivedBytes,
    );

    await _json(
      request.response,
      HttpStatus.ok,
      <String, dynamic>{
        'ok':
            true,
        'submissionId':
            submissionId,
        'fileName':
            fileName,
        'receivedBytes':
            receivedBytes,
        'status':
            'uploaded',
      },
    );
  } catch (error) {
    try {
      await gateway.failUpload(
        submissionId:
            submissionId,
        message:
            error.toString(),
      );
    } catch (_) {}

    try {
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
    } catch (_) {}

    rethrow;
  }
}

class _SupabaseGateway {
  final _WorkerConfig config;

  const _SupabaseGateway(
    this.config,
  );

  Future<_WorkerUser?> validateUser(
    String accessToken,
  ) async {
    final uri =
        Uri.parse(
      '${config.supabaseUrl}/auth/v1/user',
    );

    final response =
        await _requestJson(
      method:
          'GET',
      uri:
          uri,
      apiKey:
          config.publishableKey,
      bearerToken:
          accessToken,
    );

    if (response.statusCode !=
        HttpStatus.ok) {
      return null;
    }

    final body =
        response.json;

    if (body is! Map ||
        body['id'] == null) {
      return null;
    }

    return _WorkerUser(
      id:
          body['id'].toString(),
    );
  }

  Future<_WorkerSubmission?>
      loadOwnedSubmission({
    required String submissionId,
    required String userId,
  }) async {
    final uri =
        Uri.parse(
      '${config.supabaseUrl}/rest/v1/fabularium_submissions',
    ).replace(
      queryParameters:
          <String, String>{
        'id':
            'eq.$submissionId',
        'submitted_by':
            'eq.$userId',
        'select':
            'id,status,archive_file_name,archive_size',
        'limit':
            '1',
      },
    );

    final response =
        await _requestJson(
      method:
          'GET',
      uri:
          uri,
      apiKey:
          config.secretKey,
    );

    if (response.statusCode !=
        HttpStatus.ok) {
      throw _WorkerException(
        'Supabase submission lookup failed: '
        '${response.body}',
      );
    }

    final raw =
        response.json;

    if (raw is! List ||
        raw.isEmpty ||
        raw.first is! Map) {
      return null;
    }

    final row =
        Map<String, dynamic>.from(
      raw.first as Map,
    );

    return _WorkerSubmission(
      status:
          row['status']
                  ?.toString() ??
              '',
      archiveFileName:
          _nullableString(
        row['archive_file_name'],
      ),
      archiveSize:
          _readInt(
        row['archive_size'],
      ),
    );
  }

  Future<void> startUpload({
    required String submissionId,
    required String workerId,
    required String fileName,
    required int expectedBytes,
  }) async {
    await _rpc(
      'worker_start_fabularium_upload',
      <String, dynamic>{
        'target_submission_id':
            submissionId,
        'worker_identifier':
            workerId,
        'upload_file_name':
            fileName,
        'expected_size':
            expectedBytes,
      },
    );
  }

  Future<void> completeUpload({
    required String submissionId,
    required String fileName,
    required int receivedBytes,
  }) async {
    await _rpc(
      'worker_complete_fabularium_upload',
      <String, dynamic>{
        'target_submission_id':
            submissionId,
        'received_file_name':
            fileName,
        'received_size':
            receivedBytes,
      },
    );
  }

  Future<void> failUpload({
    required String submissionId,
    required String message,
  }) async {
    await _rpc(
      'worker_fail_fabularium_upload',
      <String, dynamic>{
        'target_submission_id':
            submissionId,
        'failure_message':
            message,
      },
    );
  }

  Future<void> _rpc(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final response =
        await _requestJson(
      method:
          'POST',
      uri:
          Uri.parse(
        '${config.supabaseUrl}/rest/v1/rpc/$name',
      ),
      apiKey:
          config.secretKey,
      body:
          payload,
    );

    if (response.statusCode <
            200 ||
        response.statusCode >=
            300) {
      throw _WorkerException(
        'Supabase RPC $name failed: '
        '${response.body}',
      );
    }
  }
}

Future<_JsonResponse> _requestJson({
  required String method,
  required Uri uri,
  required String apiKey,
  String? bearerToken,
  Map<String, dynamic>? body,
}) async {
  final client =
      HttpClient()
        ..connectionTimeout =
            const Duration(
          seconds: 20,
        );

  try {
    final request =
        await client.openUrl(
      method,
      uri,
    );

    request.headers.set(
      'apikey',
      apiKey,
    );

    if (bearerToken != null &&
        bearerToken.trim().isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }

    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json',
    );

    if (body != null) {
      request.headers.contentType =
          ContentType.json;

      request.write(
        jsonEncode(
          body,
        ),
      );
    }

    final response =
        await request.close();

    final text =
        await utf8.decoder
            .bind(response)
            .join();

    dynamic decoded;

    if (text.trim().isNotEmpty) {
      try {
        decoded =
            jsonDecode(
          text,
        );
      } catch (_) {
        decoded =
            null;
      }
    }

    return _JsonResponse(
      statusCode:
          response.statusCode,
      body:
          text,
      json:
          decoded,
    );
  } finally {
    client.close(
      force: true,
    );
  }
}

Future<void> _json(
  HttpResponse response,
  int statusCode,
  Map<String, dynamic> body,
) async {
  response.statusCode =
      statusCode;

  response.headers.contentType =
      ContentType.json;

  response.write(
    jsonEncode(
      body,
    ),
  );

  await response.close();
}

String? _bearerToken(
  HttpRequest request,
) {
  final value =
      request.headers.value(
    HttpHeaders.authorizationHeader,
  );

  if (value == null) {
    return null;
  }

  const prefix =
      'Bearer ';

  if (!value.startsWith(
    prefix,
  )) {
    return null;
  }

  final token =
      value.substring(
    prefix.length,
  ).trim();

  return token.isEmpty
      ? null
      : token;
}

String _sanitizeFileName(
  String value,
) {
  final base =
      p.basename(
    value,
  );

  final sanitized =
      base
          .replaceAll(
            RegExp(
              r'[<>:"/\\|?*\x00-\x1F]',
            ),
            '_',
          )
          .trim();

  return sanitized.isEmpty
      ? 'submission.bin'
      : sanitized;
}

String? _nullableString(
  dynamic value,
) {
  final text =
      value?.toString().trim() ??
          '';

  return text.isEmpty
      ? null
      : text;
}

int _readInt(
  dynamic value,
) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

class _WorkerConfig {
  final String supabaseUrl;
  final String publishableKey;
  final String secretKey;
  final String host;
  final int port;
  final Directory dataDirectory;
  final String workerId;

  const _WorkerConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.secretKey,
    required this.host,
    required this.port,
    required this.dataDirectory,
    required this.workerId,
  });

  static Future<_WorkerConfig> load(
    List<String> args,
  ) async {
    Map<String, dynamic> fileConfig =
        <String, dynamic>{};

    for (final arg in args) {
      if (!arg.startsWith(
        '--config=',
      )) {
        continue;
      }

      final path =
          arg.substring(
        '--config='.length,
      );

      final file =
          File(path);

      if (!await file.exists()) {
        throw _WorkerException(
          'Worker config file not found: $path',
        );
      }

      final decoded =
          jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) {
        throw const _WorkerException(
          'Worker config must be a JSON object.',
        );
      }

      fileConfig =
          Map<String, dynamic>.from(
        decoded,
      );

      break;
    }

    String readString(
      String key, {
      String defaultValue = '',
    }) {
      final fromFile =
          fileConfig[key]
              ?.toString()
              .trim();

      if (fromFile != null &&
          fromFile.isNotEmpty) {
        return fromFile;
      }

      final fromEnv =
          Platform.environment[key]
              ?.trim();

      if (fromEnv != null &&
          fromEnv.isNotEmpty) {
        return fromEnv;
      }

      return defaultValue;
    }

    final supabaseUrl =
        readString(
      'SUPABASE_URL',
    ).replaceAll(
      RegExp(r'/+$'),
      '',
    );

    final publishableKey =
        readString(
      'SUPABASE_PUBLISHABLE_KEY',
    );

    var secretKey =
        readString(
      'SUPABASE_SECRET_KEY',
    );

    // Backward compatibility with the legacy JWT-based service_role key.
    if (secretKey.isEmpty) {
      secretKey =
          readString(
        'SUPABASE_SERVICE_ROLE_KEY',
      );
    }

    if (supabaseUrl.isEmpty ||
        publishableKey.isEmpty ||
        secretKey.isEmpty) {
      throw const _WorkerException(
        'SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and '
        'SUPABASE_SECRET_KEY are required. '
        'The legacy SUPABASE_SERVICE_ROLE_KEY is also accepted.',
      );
    }

    final host =
        readString(
      'FABULARIUM_WORKER_HOST',
      defaultValue:
          '127.0.0.1',
    );

    final port =
        int.tryParse(
          readString(
            'FABULARIUM_WORKER_PORT',
            defaultValue:
                '8787',
          ),
        ) ??
        8787;

    var dataPath =
        readString(
      'FABULARIUM_WORKER_DATA_DIR',
    );

    if (dataPath.isEmpty) {
      final local =
          Platform.environment[
              'LOCALAPPDATA'];

      dataPath =
          p.join(
        local != null &&
                local.isNotEmpty
            ? local
            : Directory.systemTemp.path,
        'Fabularium',
        'Worker',
      );
    }

    final dataDirectory =
        Directory(
      dataPath,
    );

    await dataDirectory.create(
      recursive:
          true,
    );

    final workerId =
        readString(
      'FABULARIUM_WORKER_ID',
      defaultValue:
          Platform.localHostname,
    );

    return _WorkerConfig(
      supabaseUrl:
          supabaseUrl,
      publishableKey:
          publishableKey,
      secretKey:
          secretKey,
      host:
          host,
      port:
          port,
      dataDirectory:
          dataDirectory,
      workerId:
          workerId,
    );
  }
}

class _WorkerUser {
  final String id;

  const _WorkerUser({
    required this.id,
  });
}

class _WorkerSubmission {
  final String status;
  final String? archiveFileName;
  final int archiveSize;

  const _WorkerSubmission({
    required this.status,
    required this.archiveFileName,
    required this.archiveSize,
  });
}

class _JsonResponse {
  final int statusCode;
  final String body;
  final dynamic json;

  const _JsonResponse({
    required this.statusCode,
    required this.body,
    required this.json,
  });
}

class _WorkerException
    implements Exception {
  final String message;

  const _WorkerException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
