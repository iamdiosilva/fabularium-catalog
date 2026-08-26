import 'dart:convert';
import 'dart:io';

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

  static const String defaultCatalogChannelTitle =
      'Fabularium Catalog';

  static const String defaultFilesChannelTitle =
      'Fabularium Files';

  static const String defaultCatalogChannelAbout =
      'Private visual catalog used by Fabularium. '
      'Contains model previews and catalog metadata.';

  static const String defaultFilesChannelAbout =
      'Private file storage used by Fabularium. '
      'Contains model archives, package parts and manifests.';

  static const String _fileName =
      'storage_workspace.json';

  // ============================================================
  // PATH
  // ============================================================

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

  // ============================================================
  // LOAD
  // ============================================================

  Future<TelegramStorageWorkspace> load() async {
    final file =
        File(
      _filePath(),
    );

    try {
      if (await file.exists()) {
        final decoded =
            jsonDecode(
          await file.readAsString(),
        );

        if (decoded is Map) {
          final root =
              Map<String, dynamic>.from(
            decoded,
          );

          if (root['version'] == 1 &&
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

    /*
     * Migração do Storage antigo.
     *
     * O canal que já estava configurado
     * passa a ser inicialmente o Files Channel.
     *
     * Nada é perdido.
     */
    final legacyChannel =
        await _storage.loadChannel();

    if (legacyChannel != null) {
      final migrated =
          TelegramStorageWorkspace(
        catalogChannel: null,
        filesChannel: legacyChannel,
      );

      await save(
        migrated,
      );

      return migrated;
    }

    return const TelegramStorageWorkspace.empty();
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> save(
    TelegramStorageWorkspace workspace,
  ) async {
    if (workspace.usesSameChannel) {
      throw const TelegramStorageWorkspaceException(
        'Catalog Channel and Files Channel '
        'must be different Telegram channels.',
      );
    }

    final file =
        File(
      _filePath(),
    );

    await file.parent.create(
      recursive: true,
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version': 1,
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

  // ============================================================
  // LEGACY FILES CHANNEL COMPATIBILITY
  // ============================================================

  Future<void> _syncLegacyFilesChannel(
    TelegramStorageChannel? filesChannel,
  ) async {
    /*
     * storage_channel.json pertence ao Storage V1/V2.
     *
     * Enquanto ainda existirem pontos antigos do app que
     * consultem esse arquivo, ele deve representar SOMENTE
     * o Files Channel.
     *
     * createStorageChannel() salva automaticamente o canal
     * criado nesse arquivo. Isso significa que criar o
     * Catalog Channel poderia fazer o legado apontar para o
     * canal errado se não corrigíssemos aqui.
     */
    if (filesChannel == null) {
      await _storage.clearChannel();
      return;
    }

    await _storage.selectExistingChannel(
      filesChannel,
    );
  }

  // ============================================================
  // AVAILABLE CHANNELS
  // ============================================================

  Future<List<TelegramStorageChannel>>
      listAvailableChannels() {
    return _storage.listAvailableChannels();
  }

  // ============================================================
  // SELECT CATALOG
  // ============================================================

  Future<TelegramStorageWorkspace> selectCatalogChannel(
    TelegramStorageChannel channel,
  ) async {
    final current =
        await load();

    if (current.filesChannel?.id ==
        channel.id) {
      throw const TelegramStorageWorkspaceException(
        'The Catalog Channel cannot be '
        'the same as the Files Channel.',
      );
    }

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

  // ============================================================
  // SELECT FILES
  // ============================================================

  Future<TelegramStorageWorkspace> selectFilesChannel(
    TelegramStorageChannel channel,
  ) async {
    final current =
        await load();

    if (current.catalogChannel?.id ==
        channel.id) {
      throw const TelegramStorageWorkspaceException(
        'The Files Channel cannot be '
        'the same as the Catalog Channel.',
      );
    }

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

  // ============================================================
  // CREATE CATALOG CHANNEL
  // ============================================================

  Future<TelegramStorageWorkspace>
      createCatalogChannel() async {
    final channel =
        await _storage.createStorageChannel(
      title:
          defaultCatalogChannelTitle,
      about:
          defaultCatalogChannelAbout,
    );

    return selectCatalogChannel(
      channel,
    );
  }

  // ============================================================
  // CREATE FILES CHANNEL
  // ============================================================

  Future<TelegramStorageWorkspace>
      createFilesChannel() async {
    final channel =
        await _storage.createStorageChannel(
      title:
          defaultFilesChannelTitle,
      about:
          defaultFilesChannelAbout,
    );

    return selectFilesChannel(
      channel,
    );
  }

  // ============================================================
  // CLEAR CATALOG
  // ============================================================

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

  // ============================================================
  // CLEAR FILES
  // ============================================================

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

  // ============================================================
  // CLEAR ALL
  // ============================================================

  Future<void> clear() async {
    final file =
        File(
      _filePath(),
    );

    final temp =
        File(
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
