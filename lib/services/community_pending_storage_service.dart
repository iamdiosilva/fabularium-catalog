import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';
import 'telegram_storage_files_header_service.dart';
import 'telegram_storage_media_group_consolidation_service.dart';
import 'telegram_storage_media_group_service.dart';
import 'telegram_storage_workspace_service.dart';

typedef CommunityPendingStorageProgress =
    void Function(String stage);

class CommunityPendingStoragePart {
  final int index;
  final String fileName;
  final String filePath;
  final int size;
  final String sha256;

  const CommunityPendingStoragePart({
    required this.index,
    required this.fileName,
    required this.filePath,
    required this.size,
    required this.sha256,
  });

  Map<String, dynamic> toManifestJson() {
    return <String, dynamic>{
      'index': index,
      'name': fileName,
      'size': size,
      'sha256': sha256,
    };
  }
}

class CommunityPendingStorageResult {
  final String storageKey;
  final String archiveSha256;
  final String contentFingerprint;
  final int archiveSize;
  final String originalExtension;
  final int pendingChannelId;
  final int headerMessageId;
  final List<int> fileMessageIds;
  final int manifestMessageId;
  final List<CommunityPendingStoragePart> parts;

  const CommunityPendingStorageResult({
    required this.storageKey,
    required this.archiveSha256,
    required this.contentFingerprint,
    required this.archiveSize,
    required this.originalExtension,
    required this.pendingChannelId,
    required this.headerMessageId,
    required this.fileMessageIds,
    required this.manifestMessageId,
    required this.parts,
  });

  List<int> get allMessageIds => <int>{
        headerMessageId,
        ...fileMessageIds,
        manifestMessageId,
      }.where((id) => id > 0).toList()
        ..sort();
}

class CommunityPendingStorageService {
  CommunityPendingStorageService._();

  static final CommunityPendingStorageService instance =
      CommunityPendingStorageService._();

  static const int maxPartBytes =
      1024 * 1024 * 1024;

  static const int _splitBufferBytes =
      8 * 1024 * 1024;

  final TelegramStorageWorkspaceService _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStorageFilesHeaderService _headerService =
      TelegramStorageFilesHeaderService.instance;

  final TelegramStorageMediaGroupService _mediaGroupService =
      TelegramStorageMediaGroupService.instance;

  final TelegramStorageMediaGroupConsolidationService
      _consolidationService =
      TelegramStorageMediaGroupConsolidationService.instance;

  Future<CommunityPendingStorageResult> store({
    required String submissionId,
    required String archivePath,
    CommunityPendingStorageProgress? onProgress,
  }) async {
    final archiveFile = File(
      archivePath,
    );

    if (!await archiveFile.exists()) {
      throw const CommunityPendingStorageException(
        'Worker staging archive was not found.',
      );
    }

    final workspace =
        await _workspaceService.load();

    final pendingChannel =
        workspace.pendingChannel;

    if (pendingChannel == null) {
      throw const CommunityPendingStorageException(
        'Telegram Pending Channel is not configured.',
      );
    }

    if (pendingChannel.isPublic) {
      throw const CommunityPendingStorageException(
        'Telegram Pending Channel must remain private.',
      );
    }

    final journalFile =
        _journalFileFor(
      archiveFile,
    );

    await _cleanupPreviousJournal(
      pendingChannel: pendingChannel,
      journalFile: journalFile,
      onProgress: onProgress,
    );

    final storageKey =
        _createStorageKey();

    final journal =
        _PendingUploadJournal(
      version: 1,
      channelId:
          pendingChannel.id,
      storageKey:
          storageKey,
      headerMessageId: null,
      fileMessageIds:
          <int>[],
      manifestMessageId: null,
    );

    final generatedDirectory =
        Directory(
      p.join(
        archiveFile.parent.path,
        '.pending',
      ),
    );

    try {
      onProgress?.call(
        'Calculating archive SHA-256...',
      );

      final archiveSize =
          await archiveFile.length();

      final archiveSha256 =
          await _sha256File(
        archiveFile,
      );

      onProgress?.call(
        'Calculating content fingerprint...',
      );

      final contentFingerprint =
          await _calculateContentFingerprint(
        archiveFile,
      );

      onProgress?.call(
        'Preparing opaque Telegram parts...',
      );

      final parts =
          await _prepareParts(
        archiveFile: archiveFile,
        archiveSize: archiveSize,
        archiveSha256:
            archiveSha256,
        storageKey: storageKey,
        generatedDirectory:
            generatedDirectory,
        onProgress: onProgress,
      );

      if (parts.isEmpty) {
        throw const CommunityPendingStorageException(
          'No Telegram Pending parts were generated.',
        );
      }

      onProgress?.call(
        'Publishing Pending anchor...',
      );

      final headerId =
          await _headerService
              .sendHeader(
        channel:
            pendingChannel,
        text:
            storageKey,
        randomIdKey:
            'pending:$storageKey:header',
      );

      journal.headerMessageId =
          headerId;

      await _saveJournal(
        journalFile,
        journal,
      );

      final fileMessageIds =
          <int>[];

      for (var offset = 0;
          offset < parts.length;
          offset +=
              TelegramStorageMediaGroupService
                  .maxGroupItems) {
        final end =
            min<int>(
          offset +
              TelegramStorageMediaGroupService
                  .maxGroupItems,
          parts.length,
        );

        final batch =
            parts.sublist(
          offset,
          end,
        );

        final groupIndex =
            (offset ~/
                    TelegramStorageMediaGroupService
                        .maxGroupItems) +
                1;

        onProgress?.call(
          'Uploading Pending group $groupIndex '
          '(${batch.length} part${batch.length == 1 ? '' : 's'})...',
        );

        final result =
            await _mediaGroupService
                .sendGroup(
          channel:
              pendingChannel,
          items:
              batch
                  .map(
                    (part) =>
                        TelegramStorageMediaItem(
                      kind:
                          TelegramStorageMediaKind
                              .document,
                      filePath:
                          part.filePath,
                      fileName:
                          part.fileName,
                      mimeType:
                          'application/octet-stream',
                      caption:
                          '',
                      randomIdKey:
                          'pending:$storageKey:part:${part.index}',
                    ),
                  )
                  .toList(),
          onProgress:
              (_, stage) {
            onProgress?.call(
              stage,
            );
          },
        );

        fileMessageIds.addAll(
          result.messageIds,
        );

        journal.fileMessageIds
          ..clear()
          ..addAll(
            fileMessageIds,
          );

        await _saveJournal(
          journalFile,
          journal,
        );
      }

      final originalExtension =
          p.extension(
            archiveFile.path,
          )
              .toLowerCase()
              .replaceFirst(
                '.',
                '',
              );

      final manifestFile =
          File(
        p.join(
          generatedDirectory.path,
          '$storageKey.m1',
        ),
      );

      await generatedDirectory.create(
        recursive: true,
      );

      final manifest =
          <String, dynamic>{
        'v': 1,
        'kind': 'blob',
        'key': storageKey,
        'archive':
            <String, dynamic>{
          'size':
              archiveSize,
          'sha256':
              archiveSha256,
          'ext':
              originalExtension,
          'parts':
              parts.length,
        },
        'fingerprint':
            contentFingerprint,
        'items':
            parts
                .map(
                  (part) =>
                      part.toManifestJson(),
                )
                .toList(),
      };

      await manifestFile.writeAsString(
        jsonEncode(
          manifest,
        ),
        flush: true,
      );

      onProgress?.call(
        'Uploading opaque Pending manifest...',
      );

      final manifestUpload =
          await _mediaGroupService
              .sendGroup(
        channel:
            pendingChannel,
        items:
            <TelegramStorageMediaItem>[
          TelegramStorageMediaItem(
            kind:
                TelegramStorageMediaKind
                    .document,
            filePath:
                manifestFile.path,
            fileName:
                '$storageKey.m1',
            mimeType:
                'application/octet-stream',
            caption:
                '',
            randomIdKey:
                'pending:$storageKey:manifest',
          ),
        ],
        onProgress:
            (_, stage) {
          onProgress?.call(
            stage,
          );
        },
      );

      if (manifestUpload
          .messageIds
          .isEmpty) {
        throw const CommunityPendingStorageException(
          'Telegram did not return the Pending manifest message ID.',
        );
      }

      final manifestMessageId =
          manifestUpload
              .messageIds
              .single;

      journal.manifestMessageId =
          manifestMessageId;

      await _saveJournal(
        journalFile,
        journal,
      );

      final result =
          CommunityPendingStorageResult(
        storageKey:
            storageKey,
        archiveSha256:
            archiveSha256,
        contentFingerprint:
            contentFingerprint,
        archiveSize:
            archiveSize,
        originalExtension:
            originalExtension,
        pendingChannelId:
            pendingChannel.id,
        headerMessageId:
            headerId,
        fileMessageIds:
            List<int>.unmodifiable(
          fileMessageIds,
        ),
        manifestMessageId:
            manifestMessageId,
        parts:
            List<CommunityPendingStoragePart>.unmodifiable(
          parts,
        ),
      );

      onProgress?.call(
        'Verifying Pending messages...',
      );

      await _verifyMessages(
        channel:
            pendingChannel,
        messageIds:
            result.allMessageIds,
      );

      onProgress?.call(
        'Telegram Pending verified.',
      );

      return result;
    } catch (error) {
      await _rollbackJournal(
        pendingChannel:
            pendingChannel,
        journalFile:
            journalFile,
      );

      await _deleteGeneratedDirectory(
        generatedDirectory,
      );

      if (error is CommunityPendingStorageException) {
        rethrow;
      }

      throw CommunityPendingStorageException(
        error.toString(),
      );
    }
  }

  Future<void> commitLocal({
    required String archivePath,
  }) async {
    final archiveFile =
        File(
      archivePath,
    );

    final journalFile =
        _journalFileFor(
      archiveFile,
    );

    try {
      if (await journalFile.exists()) {
        await journalFile.delete();
      }
    } catch (_) {}

    await _deleteGeneratedDirectory(
      Directory(
        p.join(
          archiveFile.parent.path,
          '.pending',
        ),
      ),
    );
  }

  Future<void> deleteRemote(
    CommunityPendingStorageResult result,
  ) async {
    final workspace =
        await _workspaceService.load();

    final channel =
        workspace.pendingChannel;

    if (channel == null ||
        channel.id !=
            result.pendingChannelId) {
      throw const CommunityPendingStorageException(
        'Configured Pending Channel does not match the uploaded submission.',
      );
    }

    await _consolidationService
        .deleteMessages(
      channel:
          channel,
      messageIds:
          result.allMessageIds,
    );
  }

  Future<List<CommunityPendingStoragePart>> _prepareParts({
    required File archiveFile,
    required int archiveSize,
    required String archiveSha256,
    required String storageKey,
    required Directory generatedDirectory,
    CommunityPendingStorageProgress? onProgress,
  }) async {
    if (archiveSize <= 0) {
      throw const CommunityPendingStorageException(
        'Worker staging archive is empty.',
      );
    }

    if (archiveSize <=
        maxPartBytes) {
      return <CommunityPendingStoragePart>[
        CommunityPendingStoragePart(
          index:
              1,
          fileName:
              '$storageKey.part001',
          filePath:
              archiveFile.path,
          size:
              archiveSize,
          sha256:
              archiveSha256,
        ),
      ];
    }

    await generatedDirectory.create(
      recursive: true,
    );

    final files =
        <File>[];

    RandomAccessFile? input;

    try {
      input =
          await archiveFile.open(
        mode:
            FileMode.read,
      );

      var totalCopied =
          0;
      var partIndex =
          1;

      while (totalCopied <
          archiveSize) {
        final partFile =
            File(
          p.join(
            generatedDirectory.path,
            '$storageKey.part${partIndex.toString().padLeft(3, '0')}',
          ),
        );

        RandomAccessFile? output;

        try {
          output =
              await partFile.open(
            mode:
                FileMode.write,
          );

          final targetBytes =
              min<int>(
            maxPartBytes,
            archiveSize -
                totalCopied,
          );

          var partWritten =
              0;

          while (partWritten <
              targetBytes) {
            final readLength =
                min<int>(
              _splitBufferBytes,
              targetBytes -
                  partWritten,
            );

            final bytes =
                await input.read(
              readLength,
            );

            if (bytes.isEmpty) {
              throw const CommunityPendingStorageException(
                'Unexpected end of archive while splitting Pending parts.',
              );
            }

            await output.writeFrom(
              bytes,
            );

            partWritten +=
                bytes.length;
            totalCopied +=
                bytes.length;

            onProgress?.call(
              'Splitting archive '
              '${((totalCopied / archiveSize) * 100).toStringAsFixed(1)}%...',
            );
          }

          await output.flush();
        } finally {
          try {
            await output?.close();
          } catch (_) {}
        }

        files.add(
          partFile,
        );

        partIndex++;
      }
    } finally {
      try {
        await input?.close();
      } catch (_) {}
    }

    final parts =
        <CommunityPendingStoragePart>[];

    for (var index = 0;
        index < files.length;
        index++) {
      final file =
          files[index];

      onProgress?.call(
        'Hashing part ${index + 1}/${files.length}...',
      );

      parts.add(
        CommunityPendingStoragePart(
          index:
              index + 1,
          fileName:
              p.basename(
            file.path,
          ),
          filePath:
              file.path,
          size:
              await file.length(),
          sha256:
              await _sha256File(
            file,
          ),
        ),
      );
    }

    return parts;
  }

  Future<String> _calculateContentFingerprint(
    File archiveFile,
  ) async {
    final sevenZip =
        await _findSevenZip();

    if (sevenZip == null) {
      throw const CommunityPendingStorageException(
        '7-Zip was not found. It is required to calculate the content fingerprint.',
      );
    }

    final result =
        await Process.run(
      sevenZip,
      <String>[
        'l',
        '-slt',
        '-ba',
        archiveFile.path,
      ],
      runInShell:
          false,
    );

    if (result.exitCode !=
        0) {
      final error =
          result.stderr
              .toString()
              .trim();

      throw CommunityPendingStorageException(
        error.isEmpty
            ? '7-Zip could not inspect the submitted archive.'
            : '7-Zip could not inspect the submitted archive: $error',
      );
    }

    final text =
        result.stdout
            .toString();

    final records =
        <String>[];

    Map<String, String>
        current =
        <String, String>{};

    void flush() {
      final path =
          current['Path'];

      final size =
          current['Size'];

      final folder =
          current['Folder'];

      final attributes =
          current['Attributes'];

      final isDirectory =
          folder == '+' ||
              (attributes != null &&
                  attributes
                      .toUpperCase()
                      .startsWith(
                        'D',
                      ));

      if (path != null &&
          size != null &&
          !isDirectory) {
        final normalizedPath =
            path
                .replaceAll(
                  '\\',
                  '/',
                )
                .trim()
                .toLowerCase();

        final normalizedSize =
            size.trim();

        final crc =
            current['CRC']
                    ?.trim()
                    .toLowerCase() ??
                '';

        if (normalizedPath
            .isNotEmpty) {
          records.add(
            '$normalizedPath|$normalizedSize|$crc',
          );
        }
      }

      current =
          <String, String>{};
    }

    for (final line
        in text.split(
      RegExp(
        r'\r?\n',
      ),
    )) {
      final trimmed =
          line.trimRight();

      if (trimmed
          .trim()
          .isEmpty) {
        if (current.isNotEmpty) {
          flush();
        }

        continue;
      }

      final separator =
          trimmed.indexOf(
        ' = ',
      );

      if (separator <=
          0) {
        continue;
      }

      final key =
          trimmed
              .substring(
                0,
                separator,
              )
              .trim();

      final value =
          trimmed
              .substring(
                separator + 3,
              )
              .trim();

      current[key] =
          value;
    }

    if (current.isNotEmpty) {
      flush();
    }

    if (records.isEmpty) {
      throw const CommunityPendingStorageException(
        'The archive contains no fingerprintable files.',
      );
    }

    records.sort();

    final canonical =
        records.join(
      '\n',
    );

    return sha256
        .convert(
          utf8.encode(
            canonical,
          ),
        )
        .toString();
  }

  Future<String?> _findSevenZip() async {
    final candidates =
        <String>[];

    if (Platform.isWindows) {
      final local =
          Platform.environment[
              'LOCALAPPDATA'];

      candidates.addAll(
        <String>[
          r'C:\Program Files\7-Zip\7z.exe',
          r'C:\Program Files (x86)\7-Zip\7z.exe',
          r'C:\7-Zip\7z.exe',
          if (local != null)
            p.join(
              local,
              '7-Zip',
              '7z.exe',
            ),
        ],
      );
    } else {
      candidates.addAll(
        const <String>[
          '/usr/bin/7z',
          '/usr/bin/7zz',
          '/usr/local/bin/7z',
          '/usr/local/bin/7zz',
        ],
      );
    }

    for (final candidate
        in candidates) {
      if (candidate.trim().isEmpty) {
        continue;
      }

      try {
        if (await File(
          candidate,
        ).exists()) {
          return candidate;
        }
      } catch (_) {}
    }

    final commands =
        Platform.isWindows
            ? const <String>[
                '7z.exe',
              ]
            : const <String>[
                '7z',
                '7zz',
              ];

    for (final command
        in commands) {
      try {
        final result =
            await Process.run(
          Platform.isWindows
              ? 'where'
              : 'which',
          <String>[
            command,
          ],
          runInShell:
              Platform.isWindows,
        );

        if (result.exitCode ==
            0) {
          final paths =
              result.stdout
                  .toString()
                  .split(
                    RegExp(
                      r'[\r\n]+',
                    ),
                  )
                  .map(
                    (value) =>
                        value.trim(),
                  )
                  .where(
                    (value) =>
                        value.isNotEmpty,
                  )
                  .toList();

          if (paths.isNotEmpty) {
            return paths.first;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String> _sha256File(
    File file,
  ) async {
    final digest =
        await sha256
            .bind(
              file.openRead(),
            )
            .first;

    return digest.toString();
  }

  Future<void> _verifyMessages({
    required TelegramStorageChannel channel,
    required List<int> messageIds,
  }) async {
    final ids =
        messageIds
            .where(
              (id) =>
                  id > 0,
            )
            .toSet()
            .toList()
          ..sort();

    if (ids.isEmpty) {
      throw const CommunityPendingStorageException(
        'No Pending Telegram messages are available for verification.',
      );
    }

    final telegramClient =
        TelegramClient.instance;

    try {
      await telegramClient.disconnect();

      final client =
          await telegramClient.connect();

      final inputChannel =
          t.InputChannel(
        channelId:
            channel.id,
        accessHash:
            channel.accessHash,
      );

      final found =
          <int>{};

      const batchSize =
          100;

      for (var offset = 0;
          offset < ids.length;
          offset += batchSize) {
        final end =
            min<int>(
          offset +
              batchSize,
          ids.length,
        );

        final batch =
            ids.sublist(
          offset,
          end,
        );

        final response =
            await client
                .invoke(
          t.ChannelsGetMessages(
            channel:
                inputChannel,
            id:
                batch
                    .map<t.InputMessageBase>(
                      (id) =>
                          t.InputMessageID(
                        id:
                            id,
                      ),
                    )
                    .toList(),
          ),
        )
                .timeout(
          const Duration(
            seconds:
                60,
          ),
        );

        if (response.error !=
            null) {
          throw Exception(
            response.error!
                .errorMessage,
          );
        }

        final dynamic result =
            response.result;

        if (result == null) {
          throw const CommunityPendingStorageException(
            'Telegram returned an empty Pending verification response.',
          );
        }

        List<dynamic> messages =
            <dynamic>[];

        try {
          messages =
              List<dynamic>.from(
            result.messages as List,
          );
        } catch (_) {
          throw const CommunityPendingStorageException(
            'Telegram returned an unsupported Pending verification response.',
          );
        }

        for (final dynamic message
            in messages) {
          if (message is
              t.MessageEmpty) {
            continue;
          }

          try {
            final id =
                message.id as int;

            if (batch.contains(
              id,
            )) {
              found.add(
                id,
              );
            }
          } catch (_) {}
        }
      }

      final missing =
          ids
              .where(
                (id) =>
                    !found.contains(
                  id,
                ),
              )
              .toList();

      if (missing.isNotEmpty) {
        throw CommunityPendingStorageException(
          'Telegram Pending verification failed. '
          'Missing message IDs: ${missing.join(', ')}',
        );
      }
    } finally {
      try {
        await telegramClient.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _cleanupPreviousJournal({
    required TelegramStorageChannel pendingChannel,
    required File journalFile,
    CommunityPendingStorageProgress? onProgress,
  }) async {
    if (!await journalFile.exists()) {
      return;
    }

    onProgress?.call(
      'Cleaning previous incomplete Pending upload...',
    );

    await _rollbackJournal(
      pendingChannel:
          pendingChannel,
      journalFile:
          journalFile,
    );
  }

  Future<void> _rollbackJournal({
    required TelegramStorageChannel pendingChannel,
    required File journalFile,
  }) async {
    if (!await journalFile.exists()) {
      return;
    }

    try {
      final decoded =
          jsonDecode(
        await journalFile.readAsString(),
      );

      if (decoded is Map) {
        final journal =
            _PendingUploadJournal.fromJson(
          Map<String, dynamic>.from(
            decoded,
          ),
        );

        if (journal.channelId ==
            pendingChannel.id) {
          final ids =
              journal.allMessageIds;

          if (ids.isNotEmpty) {
            try {
              await _consolidationService
                  .deleteMessages(
                channel:
                    pendingChannel,
                messageIds:
                    ids,
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    try {
      if (await journalFile.exists()) {
        await journalFile.delete();
      }
    } catch (_) {}
  }

  File _journalFileFor(
    File archiveFile,
  ) {
    return File(
      p.join(
        archiveFile.parent.path,
        '.pending_upload.json',
      ),
    );
  }

  Future<void> _saveJournal(
    File file,
    _PendingUploadJournal journal,
  ) async {
    final temp =
        File(
      '${file.path}.tmp',
    );

    await temp.writeAsString(
      jsonEncode(
        journal.toJson(),
      ),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await temp.rename(
      file.path,
    );
  }

  Future<void> _deleteGeneratedDirectory(
    Directory directory,
  ) async {
    try {
      if (await directory.exists()) {
        await directory.delete(
          recursive:
              true,
        );
      }
    } catch (_) {}
  }

  String _createStorageKey() {
    final random =
        Random.secure();

    final bytes =
        List<int>.generate(
      16,
      (_) =>
          random.nextInt(
        256,
      ),
    );

    bytes[6] =
        (bytes[6] &
                0x0f) |
            0x40;

    bytes[8] =
        (bytes[8] &
                0x3f) |
            0x80;

    return bytes
        .map(
          (value) =>
              value
                  .toRadixString(
                    16,
                  )
                  .padLeft(
                    2,
                    '0',
                  ),
        )
        .join();
  }
}

class _PendingUploadJournal {
  final int version;
  final int channelId;
  final String storageKey;

  int? headerMessageId;
  final List<int> fileMessageIds;
  int? manifestMessageId;

  _PendingUploadJournal({
    required this.version,
    required this.channelId,
    required this.storageKey,
    required this.headerMessageId,
    required this.fileMessageIds,
    required this.manifestMessageId,
  });

  List<int> get allMessageIds => <int>{
        if (headerMessageId != null)
          headerMessageId!,
        ...fileMessageIds,
        if (manifestMessageId != null)
          manifestMessageId!,
      }.where((id) => id > 0).toList()
        ..sort();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version':
          version,
      'channelId':
          channelId,
      'storageKey':
          storageKey,
      'headerMessageId':
          headerMessageId,
      'fileMessageIds':
          fileMessageIds,
      'manifestMessageId':
          manifestMessageId,
    };
  }

  factory _PendingUploadJournal.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawFileMessageIds =
        json['fileMessageIds'];

    final fileMessageIds =
        <int>[];

    if (rawFileMessageIds is List) {
      for (final value
          in rawFileMessageIds) {
        final id =
            _readInt(
          value,
        );

        if (id != null &&
            id > 0) {
          fileMessageIds.add(
            id,
          );
        }
      }
    }

    return _PendingUploadJournal(
      version:
          _readInt(
                json['version'],
              ) ??
              1,
      channelId:
          _readInt(
                json['channelId'],
              ) ??
              0,
      storageKey:
          json['storageKey']
                  ?.toString() ??
              '',
      headerMessageId:
          _readInt(
        json['headerMessageId'],
      ),
      fileMessageIds:
          fileMessageIds,
      manifestMessageId:
          _readInt(
        json['manifestMessageId'],
      ),
    );
  }
}

int? _readInt(
  dynamic value,
) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value?.toString() ??
        '',
  );
}

class CommunityPendingStorageException
    implements Exception {
  final String message;

  const CommunityPendingStorageException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
