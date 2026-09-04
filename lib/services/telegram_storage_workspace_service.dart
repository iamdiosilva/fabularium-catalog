import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_workspace.dart';
import 'telegram_storage_service.dart';

class TelegramStorageWorkspaceService {
  TelegramStorageWorkspaceService._();

  static final TelegramStorageWorkspaceService instance =
      TelegramStorageWorkspaceService._();

  final TelegramStorageService _storage =
      TelegramStorageService.instance;

  static const String _fileName =
      'storage_workspace.json';

  String _filePath() {
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
      _fileName,
    );
  }

  Future<TelegramStorageWorkspace> load() async {
    final file = File(
      _filePath(),
    );

    try {
      if (await file.exists()) {
        final decoded = jsonDecode(
          await file.readAsString(),
        );

        if (decoded is Map) {
          final root =
              Map<String, dynamic>.from(
            decoded,
          );

          final version =
              _readInt(root['version']);

          if ((version == 1 ||
                  version == 2) &&
              root['workspace'] is Map) {
            return TelegramStorageWorkspace.fromJson(
              Map<String, dynamic>.from(
                root['workspace'] as Map,
              ),
            );
          }
        }
      }
    } catch (_) {}

    // Legacy Telegram Storage migration.
    // The old single storage channel becomes the Files Channel.
    final legacyChannel =
        await _storage.loadChannel();

    if (legacyChannel != null) {
      final migrated =
          TelegramStorageWorkspace(
        catalogChannel: null,
        filesChannel: legacyChannel,
        pendingChannel: null,
      );

      await save(
        migrated,
      );

      return migrated;
    }

    return const TelegramStorageWorkspace.empty();
  }

  Future<void> save(
    TelegramStorageWorkspace workspace,
  ) async {
    if (workspace.usesSameChannel) {
      throw const TelegramStorageWorkspaceException(
        'Catalog, Files and Pending must be different Telegram channels.',
      );
    }

    if (workspace.pendingChannel?.isPublic ==
        true) {
      throw const TelegramStorageWorkspaceException(
        'Pending Channel must remain private.',
      );
    }

    final file = File(
      _filePath(),
    );

    await file.parent.create(
      recursive: true,
    );

    final temp = File(
      '${file.path}.tmp',
    );

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version': 2,
          'kind':
              'fabularium-storage-workspace',
          'workspace':
              workspace.toJson(),
        },
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

  Future<void> _syncLegacyFilesChannel(
    TelegramStorageChannel? filesChannel,
  ) async {
    if (filesChannel == null) {
      await _storage.clearChannel();
      return;
    }

    await _storage.selectExistingChannel(
      filesChannel,
    );
  }

  Future<List<TelegramStorageChannel>>
      listAvailableChannels() {
    return _storage.listAvailableChannels();
  }

  Future<TelegramStorageWorkspace>
      selectCatalogChannel(
    TelegramStorageChannel channel,
  ) async {
    final current =
        await load();

    _ensureNotUsedByAnotherRole(
      current: current,
      selected: channel,
      role: _WorkspaceChannelRole.catalog,
    );

    final updated =
        current.copyWith(
      catalogChannel: channel,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<TelegramStorageWorkspace>
      selectFilesChannel(
    TelegramStorageChannel channel,
  ) async {
    final current =
        await load();

    _ensureNotUsedByAnotherRole(
      current: current,
      selected: channel,
      role: _WorkspaceChannelRole.files,
    );

    final updated =
        current.copyWith(
      filesChannel: channel,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<TelegramStorageWorkspace>
      selectPendingChannel(
    TelegramStorageChannel channel,
  ) async {
    if (channel.isPublic) {
      throw const TelegramStorageWorkspaceException(
        'Pending Channel must be private. Remove its public username before selecting it.',
      );
    }

    final current =
        await load();

    _ensureNotUsedByAnotherRole(
      current: current,
      selected: channel,
      role: _WorkspaceChannelRole.pending,
    );

    final updated =
        current.copyWith(
      pendingChannel: channel,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<TelegramStorageWorkspace>
      createCatalogChannel() async {
    final channel =
        await _storage.createStorageChannel(
      title:
          _generateOpaqueChannelTitle(),
      about: '',
    );

    return selectCatalogChannel(
      channel,
    );
  }

  Future<TelegramStorageWorkspace>
      createFilesChannel() async {
    final channel =
        await _storage.createStorageChannel(
      title:
          _generateOpaqueChannelTitle(),
      about: '',
    );

    return selectFilesChannel(
      channel,
    );
  }

  Future<TelegramStorageWorkspace>
      createPendingChannel() async {
    final channel =
        await _storage.createStorageChannel(
      title:
          _generateOpaqueChannelTitle(),
      about: '',
    );

    if (channel.isPublic) {
      throw const TelegramStorageWorkspaceException(
        'The newly created Pending Channel unexpectedly has a public username.',
      );
    }

    return selectPendingChannel(
      channel,
    );
  }

  Future<TelegramStorageWorkspace>
      clearCatalogChannel() async {
    final current =
        await load();

    final updated =
        current.copyWith(
      clearCatalogChannel: true,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<TelegramStorageWorkspace>
      clearFilesChannel() async {
    final current =
        await load();

    final updated =
        current.copyWith(
      clearFilesChannel: true,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<TelegramStorageWorkspace>
      clearPendingChannel() async {
    final current =
        await load();

    final updated =
        current.copyWith(
      clearPendingChannel: true,
    );

    await save(
      updated,
    );

    await _syncLegacyFilesChannel(
      updated.filesChannel,
    );

    return updated;
  }

  Future<void> clear() async {
    final file = File(
      _filePath(),
    );

    final temp = File(
      '${file.path}.tmp',
    );

    for (final candidate in <File>[
      file,
      temp,
    ]) {
      try {
        if (await candidate.exists()) {
          await candidate.delete();
        }
      } catch (_) {}
    }

    await _storage.clearChannel();
  }

  void _ensureNotUsedByAnotherRole({
    required TelegramStorageWorkspace current,
    required TelegramStorageChannel selected,
    required _WorkspaceChannelRole role,
  }) {
    final otherChannels =
        <TelegramStorageChannel?>[
      if (role != _WorkspaceChannelRole.catalog)
        current.catalogChannel,
      if (role != _WorkspaceChannelRole.files)
        current.filesChannel,
      if (role != _WorkspaceChannelRole.pending)
        current.pendingChannel,
    ];

    if (otherChannels.any(
      (channel) =>
          channel?.id == selected.id,
    )) {
      throw const TelegramStorageWorkspaceException(
        'Each Telegram workspace role must use a different channel.',
      );
    }
  }

  String _generateOpaqueChannelTitle() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

    // UUID v4 variant bits.
    bytes[6] =
        (bytes[6] & 0x0f) | 0x40;
    bytes[8] =
        (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map(
          (value) => value
              .toRadixString(16)
              .padLeft(2, '0'),
        )
        .join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

enum _WorkspaceChannelRole {
  catalog,
  files,
  pending,
}

int _readInt(dynamic value) {
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

class TelegramStorageWorkspaceException
    implements Exception {
  final String message;

  const TelegramStorageWorkspaceException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
