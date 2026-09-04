import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';
import 'telegram_storage_files_header_service.dart';
import 'telegram_storage_media_group_consolidation_service.dart';
import 'telegram_storage_workspace_service.dart';

typedef CommunityOfficialPublishProgress =
    void Function(String stage);

class CommunityOfficialPublishPart {
  final int index;
  final int groupIndex;
  final String fileName;
  final int size;
  final String sha256;
  final int messageId;

  const CommunityOfficialPublishPart({
    required this.index,
    required this.groupIndex,
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.messageId,
  });

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'partIndex': index,
        'groupIndex': groupIndex,
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
        'messageId': messageId,
      };
}

class CommunityOfficialPublishGroup {
  final int groupIndex;
  final int? groupedId;

  const CommunityOfficialPublishGroup({
    required this.groupIndex,
    required this.groupedId,
  });

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'groupIndex': groupIndex,
        'groupedId': groupedId,
      };
}

class CommunityOfficialPublishResult {
  final int catalogChannelId;
  final int catalogAccessHash;
  final String catalogChannelTitle;
  final int catalogAnchorMessageId;
  final int filesChannelId;
  final int filesAccessHash;
  final String filesChannelTitle;
  final int filesHeaderMessageId;
  final int filesManifestMessageId;
  final String storageKey;
  final String archiveExtension;
  final Map<String, dynamic> manifest;
  final List<CommunityOfficialPublishGroup> fileGroups;
  final List<CommunityOfficialPublishPart> parts;

  const CommunityOfficialPublishResult({
    required this.catalogChannelId,
    required this.catalogAccessHash,
    required this.catalogChannelTitle,
    required this.catalogAnchorMessageId,
    required this.filesChannelId,
    required this.filesAccessHash,
    required this.filesChannelTitle,
    required this.filesHeaderMessageId,
    required this.filesManifestMessageId,
    required this.storageKey,
    required this.archiveExtension,
    required this.manifest,
    required this.fileGroups,
    required this.parts,
  });

  List<int> get catalogMessageIds => <int>[catalogAnchorMessageId];

  List<int> get filesMessageIds => <int>{
        filesHeaderMessageId,
        ...parts.map((part) => part.messageId),
        filesManifestMessageId,
      }.where((id) => id > 0).toList()
        ..sort();
}

class CommunityOfficialPublishService {
  CommunityOfficialPublishService._();

  static final CommunityOfficialPublishService instance =
      CommunityOfficialPublishService._();

  static const int _maxGroupItems = 10;
  static const int _manifestMaxBytes = 8 * 1024 * 1024;

  final TelegramStorageWorkspaceService _workspace =
      TelegramStorageWorkspaceService.instance;

  final TelegramStorageFilesHeaderService _header =
      TelegramStorageFilesHeaderService.instance;

  final TelegramStorageMediaGroupConsolidationService _delete =
      TelegramStorageMediaGroupConsolidationService.instance;

  final TelegramClient _telegram =
      TelegramClient.instance;

  Future<CommunityOfficialPublishResult> publish({
    required String storageKey,
    required int pendingChannelId,
    required List<int> pendingFileMessageIds,
    required int pendingManifestMessageId,
    CommunityOfficialPublishProgress? onProgress,
  }) async {
    final workspace =
        await _workspace.load();

    final pending =
        workspace.pendingChannel;
    final catalog =
        workspace.catalogChannel;
    final files =
        workspace.filesChannel;

    if (pending == null ||
        catalog == null ||
        files == null) {
      throw const CommunityOfficialPublishException(
        'Catalog, Files and Pending Telegram channels must be configured.',
      );
    }

    if (pending.id != pendingChannelId) {
      throw const CommunityOfficialPublishException(
        'Configured Pending Channel does not match the submission.',
      );
    }

    if (pending.isPublic) {
      throw const CommunityOfficialPublishException(
        'Pending Channel must remain private.',
      );
    }

    if (pendingFileMessageIds.isEmpty ||
        pendingManifestMessageId <= 0 ||
        storageKey.trim().isEmpty) {
      throw const CommunityOfficialPublishException(
        'Submission Pending storage metadata is incomplete.',
      );
    }

    onProgress?.call(
      'Reading Pending manifest...',
    );

    final manifest =
        await _readManifest(
      channel: pending,
      messageId: pendingManifestMessageId,
    );

    if (manifest['key']?.toString() != storageKey) {
      throw const CommunityOfficialPublishException(
        'Pending manifest storageKey mismatch.',
      );
    }

    final manifestParts =
        _readManifestParts(
      manifest,
    );

    if (manifestParts.length !=
        pendingFileMessageIds.length) {
      throw const CommunityOfficialPublishException(
        'Pending manifest part count does not match Telegram messages.',
      );
    }

    String extension =
        'bin';

    final archive =
        manifest['archive'];

    if (archive is Map) {
      final raw =
          archive['ext']?.toString().trim().toLowerCase() ?? '';

      if (RegExp(r'^[a-z0-9]{1,12}$').hasMatch(raw)) {
        extension =
            raw;
      }
    }

    final createdCatalog =
        <int>[];
    final createdFiles =
        <int>[];

    try {
      onProgress?.call(
        'Publishing opaque Official Catalog anchor...',
      );

      final catalogAnchor =
          await _header.sendHeader(
        channel: catalog,
        text: _opaqueKey(),
        randomIdKey:
            'official:catalog:$storageKey',
      );

      createdCatalog.add(
        catalogAnchor,
      );

      onProgress?.call(
        'Publishing opaque Official Files anchor...',
      );

      final filesHeader =
          await _header.sendHeader(
        channel: files,
        text: _opaqueKey(),
        randomIdKey:
            'official:files:$storageKey',
      );

      createdFiles.add(
        filesHeader,
      );

      final groups =
          <CommunityOfficialPublishGroup>[];
      final parts =
          <CommunityOfficialPublishPart>[];

      for (var offset = 0;
          offset < pendingFileMessageIds.length;
          offset += _maxGroupItems) {
        final end =
            min<int>(
          offset + _maxGroupItems,
          pendingFileMessageIds.length,
        );

        final sourceIds =
            pendingFileMessageIds.sublist(
          offset,
          end,
        );

        final groupIndex =
            (offset ~/ _maxGroupItems) + 1;

        onProgress?.call(
          'Reusing Pending documents in Official Files group $groupIndex...',
        );

        final copied =
            await _copyDocuments(
          source: pending,
          destination: files,
          sourceMessageIds: sourceIds,
          randomIdKeys:
              List<String>.generate(
            sourceIds.length,
            (index) =>
                'official:$storageKey:part:${offset + index + 1}',
          ),
        );

        createdFiles.addAll(
          copied.messageIds,
        );

        groups.add(
          CommunityOfficialPublishGroup(
            groupIndex: groupIndex,
            groupedId: copied.groupedId,
          ),
        );

        for (var index = 0;
            index < copied.messageIds.length;
            index++) {
          final metadata =
              manifestParts[offset + index];

          parts.add(
            CommunityOfficialPublishPart(
              index: metadata.index,
              groupIndex: groupIndex,
              fileName: metadata.fileName,
              size: metadata.size,
              sha256: metadata.sha256,
              messageId: copied.messageIds[index],
            ),
          );
        }
      }

      onProgress?.call(
        'Reusing Pending manifest in Official Files...',
      );

      final manifestCopy =
          await _copyDocuments(
        source: pending,
        destination: files,
        sourceMessageIds:
            <int>[
          pendingManifestMessageId,
        ],
        randomIdKeys:
            <String>[
          'official:$storageKey:manifest',
        ],
      );

      final officialManifest =
          manifestCopy.messageIds.single;

      createdFiles.add(
        officialManifest,
      );

      onProgress?.call(
        'Verifying Official Catalog...',
      );

      await _verify(
        catalog,
        createdCatalog,
      );

      onProgress?.call(
        'Verifying Official Files...',
      );

      await _verify(
        files,
        createdFiles,
      );

      onProgress?.call(
        'Official Telegram publication verified.',
      );

      return CommunityOfficialPublishResult(
        catalogChannelId: catalog.id,
        catalogAccessHash: catalog.accessHash,
        catalogChannelTitle: catalog.title,
        catalogAnchorMessageId: catalogAnchor,
        filesChannelId: files.id,
        filesAccessHash: files.accessHash,
        filesChannelTitle: files.title,
        filesHeaderMessageId: filesHeader,
        filesManifestMessageId: officialManifest,
        storageKey: storageKey,
        archiveExtension: extension,
        manifest:
            Map<String, dynamic>.from(
          manifest,
        ),
        fileGroups:
            List.unmodifiable(
          groups,
        ),
        parts:
            List.unmodifiable(
          parts,
        ),
      );
    } catch (error) {
      try {
        await _delete.deleteMessages(
          channel: catalog,
          messageIds: createdCatalog,
        );
      } catch (_) {}

      try {
        await _delete.deleteMessages(
          channel: files,
          messageIds: createdFiles,
        );
      } catch (_) {}

      rethrow;
    }
  }

  Future<void> deletePending({
    required int pendingChannelId,
    required Iterable<int> messageIds,
  }) async {
    final workspace =
        await _workspace.load();

    final pending =
        workspace.pendingChannel;

    if (pending == null ||
        pending.id != pendingChannelId) {
      throw const CommunityOfficialPublishException(
        'Configured Pending Channel does not match cleanup target.',
      );
    }

    await _delete.deleteMessages(
      channel: pending,
      messageIds: messageIds,
    );
  }

  Future<Map<String, dynamic>> _readManifest({
    required TelegramStorageChannel channel,
    required int messageId,
  }) async {
    await _telegram.disconnect();

    final client =
        await _telegram.connect();

    final response =
        await client.invoke(
      t.ChannelsGetMessages(
        channel:
            t.InputChannel(
          channelId: channel.id,
          accessHash: channel.accessHash,
        ),
        id:
            <t.InputMessageBase>[
          t.InputMessageID(
            id: messageId,
          ),
        ],
      ),
    ).timeout(
      const Duration(
        seconds: 60,
      ),
    );

    if (response.error != null) {
      throw Exception(
        response.error!
            .errorMessage,
      );
    }

    final dynamic result =
        response.result;

    final messages =
        List<dynamic>.from(
      result.messages as List,
    );

    if (messages.length != 1) {
      throw const CommunityOfficialPublishException(
        'Pending manifest message was not found.',
      );
    }

    final dynamic document =
        messages.single.media?.document;

    if (document == null ||
        document.runtimeType.toString() !=
            'Document') {
      throw const CommunityOfficialPublishException(
        'Pending manifest is not a Telegram document.',
      );
    }

    final size =
        document.size as int;

    if (size <= 0 ||
        size > _manifestMaxBytes) {
      throw const CommunityOfficialPublishException(
        'Pending manifest size is invalid.',
      );
    }

    final dataClient =
        await _telegram
            .getClientForDataCenter(
      document.dcId as int,
    );

    final location =
        t.InputDocumentFileLocation(
      id: document.id as int,
      accessHash: document.accessHash as int,
      fileReference:
          Uint8List.fromList(
        List<int>.from(
          document.fileReference as List,
        ),
      ),
      thumbSize: '',
    );

    final builder =
        BytesBuilder(
      copy: false,
    );

    const chunkSize =
        512 * 1024;

    var offset =
        0;

    while (offset <
        size) {
      final fileResponse =
          await dataClient.invoke(
        t.UploadGetFile(
          precise: false,
          cdnSupported: false,
          location: location,
          offset: offset,
          limit: chunkSize,
        ),
      ).timeout(
        const Duration(
          seconds: 60,
        ),
      );

      if (fileResponse.error !=
          null) {
        throw Exception(
          fileResponse.error!
              .errorMessage,
        );
      }

      final dynamic fileResult =
          fileResponse.result;

      final bytes =
          List<int>.from(
        fileResult.bytes as List,
      );

      if (bytes.isEmpty) {
        break;
      }

      builder.add(
        bytes,
      );

      offset +=
          bytes.length;

      if (bytes.length <
          chunkSize) {
        break;
      }
    }

    await _telegram.disconnect();

    final bytes =
        builder.takeBytes();

    if (bytes.length !=
        size) {
      throw const CommunityOfficialPublishException(
        'Pending manifest download was incomplete.',
      );
    }

    final decoded =
        jsonDecode(
      utf8.decode(
        bytes,
      ),
    );

    if (decoded is! Map) {
      throw const CommunityOfficialPublishException(
        'Pending manifest JSON is invalid.',
      );
    }

    return Map<String, dynamic>.from(
      decoded,
    );
  }

  List<_ManifestPart> _readManifestParts(
    Map<String, dynamic> manifest,
  ) {
    final raw =
        manifest['items'];

    if (raw is! List ||
        raw.isEmpty) {
      throw const CommunityOfficialPublishException(
        'Pending manifest contains no parts.',
      );
    }

    final result =
        <_ManifestPart>[];

    for (final value
        in raw) {
      if (value is! Map) {
        continue;
      }

      final item =
          Map<String, dynamic>.from(
        value,
      );

      final index =
          _readInt(
        item['index'],
      );

      final fileName =
          item['name']?.toString().trim() ?? '';

      final size =
          _readInt(
        item['size'],
      );

      final sha256 =
          item['sha256']?.toString().trim().toLowerCase() ?? '';

      if (index <= 0 ||
          fileName.isEmpty ||
          size <= 0 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(
            sha256,
          )) {
        throw const CommunityOfficialPublishException(
          'Pending manifest part metadata is invalid.',
        );
      }

      result.add(
        _ManifestPart(
          index: index,
          fileName: fileName,
          size: size,
          sha256: sha256,
        ),
      );
    }

    result.sort(
      (a, b) =>
          a.index.compareTo(
        b.index,
      ),
    );

    return result;
  }

  Future<_CopiedGroup> _copyDocuments({
    required TelegramStorageChannel source,
    required TelegramStorageChannel destination,
    required List<int> sourceMessageIds,
    required List<String> randomIdKeys,
  }) async {
    await _telegram.disconnect();

    final client =
        await _telegram.connect();

    final response =
        await client.invoke(
      t.ChannelsGetMessages(
        channel:
            t.InputChannel(
          channelId: source.id,
          accessHash: source.accessHash,
        ),
        id:
            sourceMessageIds
                .map<t.InputMessageBase>(
                  (id) =>
                      t.InputMessageID(
                    id: id,
                  ),
                )
                .toList(),
      ),
    ).timeout(
      const Duration(
        seconds: 60,
      ),
    );

    if (response.error != null) {
      throw Exception(
        response.error!
            .errorMessage,
      );
    }

    final dynamic result =
        response.result;

    final messages =
        List<dynamic>.from(
      result.messages as List,
    );

    final byId =
        <int, dynamic>{};

    for (final dynamic message
        in messages) {
      if (message is
          t.MessageEmpty) {
        continue;
      }

      byId[message.id as int] =
          message;
    }

    final prepared =
        <t.InputSingleMedia>[];

    final randomIds =
        <int>[];

    for (var index = 0;
        index < sourceMessageIds.length;
        index++) {
      final sourceId =
          sourceMessageIds[index];

      final dynamic document =
          byId[sourceId]
              ?.media
              ?.document;

      if (document == null ||
          document.runtimeType.toString() !=
              'Document') {
        throw CommunityOfficialPublishException(
          'Pending source message $sourceId is not a reusable document.',
        );
      }

      final randomId =
          _stableRandomId(
        randomIdKeys[index],
      );

      randomIds.add(
        randomId,
      );

      prepared.add(
        t.InputSingleMedia(
          media:
              t.InputMediaDocument(
            spoiler: false,
            id:
                t.InputDocument(
              id: document.id as int,
              accessHash: document.accessHash as int,
              fileReference: document.fileReference,
            ),
          ),
          randomId: randomId,
          message: '',
        ),
      );
    }

    final peer =
        t.InputPeerChannel(
      channelId: destination.id,
      accessHash: destination.accessHash,
    );

    dynamic publish;

    if (prepared.length ==
        1) {
      final item =
          prepared.single;

      publish =
          await client.invoke(
        t.MessagesSendMedia(
          silent: true,
          background: true,
          clearDraft: false,
          noforwards: false,
          updateStickersetsOrder: false,
          invertMedia: false,
          allowPaidFloodskip: false,
          peer: peer,
          media: item.media,
          message: '',
          randomId: item.randomId,
        ),
      ).timeout(
        const Duration(
          minutes: 2,
        ),
      );
    } else {
      publish =
          await client.invoke(
        t.MessagesSendMultiMedia(
          silent: true,
          background: true,
          clearDraft: false,
          noforwards: false,
          updateStickersetsOrder: false,
          invertMedia: false,
          allowPaidFloodskip: false,
          peer: peer,
          multiMedia: prepared,
        ),
      ).timeout(
        const Duration(
          minutes: 2,
        ),
      );
    }

    if (publish.error != null) {
      throw Exception(
        publish.error!
            .errorMessage,
      );
    }

    final copied =
        _extractSentGroup(
      publish.result,
      randomIds,
    );

    await _telegram.disconnect();

    return copied;
  }

  Future<void> _verify(
    TelegramStorageChannel channel,
    List<int> ids,
  ) async {
    await _telegram.disconnect();

    final client =
        await _telegram.connect();

    final response =
        await client.invoke(
      t.ChannelsGetMessages(
        channel:
            t.InputChannel(
          channelId: channel.id,
          accessHash: channel.accessHash,
        ),
        id:
            ids
                .map<t.InputMessageBase>(
                  (id) =>
                      t.InputMessageID(
                    id: id,
                  ),
                )
                .toList(),
      ),
    ).timeout(
      const Duration(
        seconds: 60,
      ),
    );

    if (response.error != null) {
      throw Exception(
        response.error!
            .errorMessage,
      );
    }

    final dynamic result =
        response.result;

    final found =
        <int>{};

    for (final dynamic message
        in List<dynamic>.from(
      result.messages as List,
    )) {
      if (message is
          t.MessageEmpty) {
        continue;
      }

      found.add(
        message.id as int,
      );
    }

    await _telegram.disconnect();

    if (!ids.every(
      found.contains,
    )) {
      throw const CommunityOfficialPublishException(
        'Official Telegram verification failed.',
      );
    }
  }

  String _opaqueKey() {
    final random =
        Random.secure();

    return List<int>.generate(
      16,
      (_) =>
          random.nextInt(
        256,
      ),
    )
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

  static int _stableRandomId(
    String value,
  ) {
    const int offset =
        1469598103934665603;
    const int prime =
        1099511628211;
    const int mask =
        0x7FFFFFFFFFFFFFFF;

    int hash =
        offset;

    for (final codeUnit
        in value.codeUnits) {
      hash ^=
          codeUnit;
      hash =
          (hash * prime) &
              mask;
    }

    return hash == 0
        ? 1
        : hash;
  }
}

class _ManifestPart {
  final int index;
  final String fileName;
  final int size;
  final String sha256;

  const _ManifestPart({
    required this.index,
    required this.fileName,
    required this.size,
    required this.sha256,
  });
}

class _CopiedGroup {
  final List<int> messageIds;
  final int? groupedId;

  const _CopiedGroup({
    required this.messageIds,
    required this.groupedId,
  });
}

_CopiedGroup _extractSentGroup(
  dynamic updates,
  List<int> randomIds,
) {
  if (updates.runtimeType.toString() ==
      'UpdateShortSentMessage') {
    return _CopiedGroup(
      messageIds:
          <int>[
        updates.id as int,
      ],
      groupedId:
          null,
    );
  }

  final mapping =
      <int, int>{};

  final fallback =
      <int>[];

  int? groupedId;

  final rawUpdates =
      List<dynamic>.from(
    updates.updates as List,
  );

  for (final dynamic update
      in rawUpdates) {
    final type =
        update.runtimeType.toString();

    if (type ==
        'UpdateMessageID') {
      mapping[
          update.randomId
              as int] =
          update.id as int;
    } else if (type ==
            'UpdateNewChannelMessage' ||
        type ==
            'UpdateNewMessage') {
      final dynamic message =
          update.message;

      fallback.add(
        message.id as int,
      );

      final dynamic gid =
          message.groupedId;

      if (gid is int) {
        groupedId ??=
            gid;
      }
    }
  }

  final ordered =
      <int>[];

  for (final randomId
      in randomIds) {
    final id =
        mapping[randomId];

    if (id != null) {
      ordered.add(
        id,
      );
    }
  }

  if (ordered.length ==
      randomIds.length) {
    return _CopiedGroup(
      messageIds:
          ordered,
      groupedId:
          groupedId,
    );
  }

  fallback.sort();

  if (fallback.length !=
      randomIds.length) {
    throw const CommunityOfficialPublishException(
      'Could not determine Telegram message IDs.',
    );
  }

  return _CopiedGroup(
    messageIds:
        fallback,
    groupedId:
        groupedId,
  );
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

class CommunityOfficialPublishException
    implements Exception {
  final String message;

  const CommunityOfficialPublishException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
