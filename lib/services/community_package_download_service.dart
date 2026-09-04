import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;

import '../features/community/data/community_catalog_repository.dart';
import '../features/community/domain/community_catalog_model.dart';
import '../features/community/domain/community_download_ticket.dart';
import '../models/download_task.dart';
import '../models/telegram_media.dart';
import 'download_queue_service.dart';
import 'telegram_client.dart';
import 'telegram_file_service.dart';
import 'telegram_service.dart';

class CommunityDownloadHandle {
  final List<DownloadTask> tasks;
  final Future<String> completed;

  const CommunityDownloadHandle({
    required this.tasks,
    required this.completed,
  });
}

class CommunityPackageDownloadService {
  CommunityPackageDownloadService._();

  static final CommunityPackageDownloadService instance =
      CommunityPackageDownloadService._();

  final CommunityCatalogRepository _repository =
      CommunityCatalogRepository.instance;

  final TelegramClient _telegram = TelegramClient.instance;
  final TelegramService _telegramAuth = TelegramService.instance;
  final DownloadQueueService _queue = DownloadQueueService.instance;
  final TelegramFileService _files = TelegramFileService.instance;

  Future<CommunityDownloadHandle> startDownload(
    CommunityCatalogModel model,
  ) async {
    if (!_telegramAuth.isAuthenticated) {
      throw const CommunityPackageDownloadException(
        'Download Access is not connected.',
      );
    }

    final ticket = await _repository.loadDownloadTicket(model.modelId);
    final channel = await _resolvePublicChannel(ticket.filesUsername);
    final remoteMedia = await _loadPartMedia(
      model: model,
      ticket: ticket,
      channel: channel,
    );

    final tasks = <DownloadTask>[];
    final groupTitle = 'Community - ${model.name}';

    for (final media in remoteMedia) {
      tasks.add(
        _queue.enqueue(
          media: media,
          groupTitle: groupTitle,
        ),
      );
    }

    return CommunityDownloadHandle(
      tasks: List<DownloadTask>.unmodifiable(tasks),
      completed: _assembleWhenReady(
        model: model,
        ticket: ticket,
        tasks: tasks,
      ),
    );
  }

  Future<_ResolvedChannel> _resolvePublicChannel(String username) async {
    final normalized = username.trim().replaceFirst('@', '');

    if (normalized.isEmpty) {
      throw const CommunityPackageDownloadException(
        'Official download routing is unavailable.',
      );
    }

    try {
      await _telegram.disconnect();
      final client = await _telegram.connect();

      final response = await client.invoke(
        t.ContactsResolveUsername(
          username: normalized,
        ),
      ).timeout(const Duration(seconds: 30));

      if (response.error != null) {
        throw Exception(response.error!.errorMessage);
      }

      final dynamic result = response.result;
      List<dynamic> chats = <dynamic>[];

      try {
        chats = List<dynamic>.from(result.chats as List);
      } catch (_) {}

      for (final dynamic raw in chats) {
        if (raw is! t.Channel) continue;
        final accessHash = raw.accessHash;
        if (accessHash == null) continue;

        return _ResolvedChannel(
          id: raw.id,
          accessHash: accessHash,
        );
      }

      throw const CommunityPackageDownloadException(
        'Official download channel could not be resolved.',
      );
    } finally {
      try {
        await _telegram.disconnect();
      } catch (_) {}
    }
  }

  Future<List<TelegramMedia>> _loadPartMedia({
    required CommunityCatalogModel model,
    required CommunityDownloadTicket ticket,
    required _ResolvedChannel channel,
  }) async {
    final messageIds = ticket.parts.map((part) => part.messageId).toList();

    if (messageIds.any((id) => id <= 0)) {
      throw const CommunityPackageDownloadException(
        'Download ticket contains invalid Telegram message IDs.',
      );
    }

    try {
      await _telegram.disconnect();
      final client = await _telegram.connect();

      final response = await client.invoke(
        t.ChannelsGetMessages(
          channel: t.InputChannel(
            channelId: channel.id,
            accessHash: channel.accessHash,
          ),
          id: messageIds
              .map<t.InputMessageBase>((id) => t.InputMessageID(id: id))
              .toList(),
        ),
      ).timeout(const Duration(seconds: 60));

      if (response.error != null) {
        throw Exception(response.error!.errorMessage);
      }

      final dynamic result = response.result;
      List<dynamic> messages = <dynamic>[];

      try {
        messages = List<dynamic>.from(result.messages as List);
      } catch (_) {}

      final byId = <int, dynamic>{};

      for (final dynamic message in messages) {
        if (message is t.MessageEmpty) continue;
        try {
          byId[message.id as int] = message;
        } catch (_) {}
      }

      final media = <TelegramMedia>[];

      for (final part in ticket.parts) {
        final dynamic message = byId[part.messageId];
        if (message == null) {
          throw CommunityPackageDownloadException(
            'Official file part ${part.partIndex} was not found.',
          );
        }

        final dynamic document = message.media?.document;
        if (document == null ||
            document.runtimeType.toString() != 'Document') {
          throw CommunityPackageDownloadException(
            'Official file part ${part.partIndex} is not a Telegram document.',
          );
        }

        final documentSize = document.size as int;
        if (part.size > 0 && documentSize != part.size) {
          throw CommunityPackageDownloadException(
            'Official file part ${part.partIndex} size does not match the catalog.',
          );
        }

        final fileReference = Uint8List.fromList(
          List<int>.from(document.fileReference as List),
        );

        final padded = part.partIndex.toString().padLeft(3, '0');

        media.add(
          TelegramMedia(
            type: TelegramMediaType.document,
            cacheKey: 'community_${model.modelId}_${part.messageId}',
            fileName: '${model.modelId}.part$padded',
            mimeType: 'application/octet-stream',
            size: documentSize,
            dcId: document.dcId as int,
            location: t.InputDocumentFileLocation(
              id: document.id as int,
              accessHash: document.accessHash as int,
              fileReference: fileReference,
              thumbSize: '',
            ),
            previewLocation: null,
            previewSize: null,
          ),
        );
      }

      return media;
    } finally {
      try {
        await _telegram.disconnect();
      } catch (_) {}
    }
  }

  Future<String> _assembleWhenReady({
    required CommunityCatalogModel model,
    required CommunityDownloadTicket ticket,
    required List<DownloadTask> tasks,
  }) async {
    while (true) {
      final failed = tasks.where((task) => task.isFailed).toList();

      if (failed.isNotEmpty) {
        throw CommunityPackageDownloadException(
          failed.first.errorMessage ?? 'A package part failed to download.',
        );
      }

      if (tasks.every((task) => task.isCompleted)) break;

      await Future<void>.delayed(const Duration(milliseconds: 450));
    }

    final paths = tasks.map((task) => task.filePath).toList();
    if (paths.any((path) => path == null)) {
      throw const CommunityPackageDownloadException(
        'Downloaded package parts are missing from disk.',
      );
    }

    final firstFile = File(paths.first!);
    final parent = firstFile.parent;
    final safeName = _files.sanitizeFileName(model.name);
    final extension = _safeExtension(ticket.archiveExtension);
    final output = File(p.join(parent.path, '$safeName.$extension'));
    final temporary = File('${output.path}.assembling');

    if (await temporary.exists()) await temporary.delete();

    final sink = temporary.openWrite();
    try {
      for (final path in paths) {
        final file = File(path!);
        if (!await file.exists()) {
          throw const CommunityPackageDownloadException(
            'A downloaded package part disappeared before assembly.',
          );
        }
        await sink.addStream(file.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final actualSize = await temporary.length();
    if (ticket.archiveSize > 0 && actualSize != ticket.archiveSize) {
      await temporary.delete();
      throw CommunityPackageDownloadException(
        'Assembled archive size mismatch: $actualSize/${ticket.archiveSize}.',
      );
    }

    if (ticket.archiveSha256.trim().isNotEmpty) {
      final digest = await sha256.bind(temporary.openRead()).first;
      if (digest.toString().toLowerCase() !=
          ticket.archiveSha256.toLowerCase()) {
        await temporary.delete();
        throw const CommunityPackageDownloadException(
          'The completed archive failed SHA-256 verification.',
        );
      }
    }

    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);

    return output.path;
  }

  String _safeExtension(String value) {
    final normalized = value.trim().toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,12}$').hasMatch(normalized)) {
      return normalized;
    }
    return 'bin';
  }
}

class _ResolvedChannel {
  final int id;
  final int accessHash;

  const _ResolvedChannel({
    required this.id,
    required this.accessHash,
  });
}

class CommunityPackageDownloadException implements Exception {
  final String message;

  const CommunityPackageDownloadException(this.message);

  @override
  String toString() => message;
}
