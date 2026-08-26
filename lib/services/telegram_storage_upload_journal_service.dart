import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/telegram_storage_upload_journal.dart';

class TelegramStorageUploadJournalService {
  TelegramStorageUploadJournalService._();
  static final TelegramStorageUploadJournalService instance =
      TelegramStorageUploadJournalService._();
  static const String _directoryName = 'storage_journal';

  String _directoryPath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final basePath = localAppData != null && localAppData.isNotEmpty
        ? localAppData
        : Directory.systemTemp.path;
    return p.join(basePath, 'Fabularium', 'Telegram', _directoryName);
  }

  Directory get directory => Directory(_directoryPath());

  File _journalFile(String packageId) {
    final safe = packageId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(p.join(_directoryPath(), '$safe.json'));
  }

  Future<TelegramStorageUploadJournal?> load(String packageId) async {
    final file = _journalFile(packageId);
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final root = Map<String, dynamic>.from(decoded);
      if (root['version'] != 3 ||
          root['kind'] != 'fabularium-storage-upload-journal') {
        return null;
      }
      return TelegramStorageUploadJournal.fromJson(root);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TelegramStorageUploadJournal journal) async {
    final file = _journalFile(journal.packageId);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(encoder.convert(journal.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<List<TelegramStorageUploadJournal>> list() async {
    final folder = directory;
    if (!await folder.exists()) return <TelegramStorageUploadJournal>[];
    final journals = <TelegramStorageUploadJournal>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final root = Map<String, dynamic>.from(decoded);
        if (root['version'] != 3 ||
            root['kind'] != 'fabularium-storage-upload-journal') {
          continue;
        }
        journals.add(TelegramStorageUploadJournal.fromJson(root));
      } catch (_) {}
    }
    journals.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return journals;
  }

  Future<List<TelegramStorageUploadJournal>> listIncomplete() async {
    final journals = await list();
    return journals.where((journal) =>
        journal.status == TelegramStorageUploadStatus.preparing ||
        journal.status == TelegramStorageUploadStatus.uploading ||
        journal.status == TelegramStorageUploadStatus.failed ||
        journal.status == TelegramStorageUploadStatus.removing).toList();
  }

  Future<List<TelegramStorageUploadJournal>> listFailed() async =>
      (await list()).where((journal) => journal.isFailed).toList();

  Future<List<TelegramStorageUploadJournal>> listStored() async =>
      (await list()).where((journal) => journal.isStored).toList();

  Future<void> delete(String packageId) async {
    final file = _journalFile(packageId);
    final temp = File('${file.path}.tmp');
    for (final candidate in <File>[file, temp]) {
      try {
        if (await candidate.exists()) await candidate.delete();
      } catch (_) {}
    }
  }

  Future<TelegramStorageUploadJournal> markUploading(
      TelegramStorageUploadJournal journal) async {
    final updated = journal.copyWith(
      status: TelegramStorageUploadStatus.uploading,
      lastError: null,
    );
    await save(updated);
    return updated;
  }

  Future<TelegramStorageUploadJournal> markFailed(
      TelegramStorageUploadJournal journal, Object error) async {
    final updated = journal.copyWith(
      status: TelegramStorageUploadStatus.failed,
      lastError: error.toString(),
    );
    await save(updated);
    return updated;
  }

  Future<TelegramStorageUploadJournal> markStored(
      TelegramStorageUploadJournal journal) async {
    final updated = journal.copyWith(
      status: TelegramStorageUploadStatus.stored,
      lastError: null,
    );
    await save(updated);
    return updated;
  }

  Future<TelegramStorageUploadJournal> markRemoving(
      TelegramStorageUploadJournal journal) async {
    final updated = journal.copyWith(status: TelegramStorageUploadStatus.removing);
    await save(updated);
    return updated;
  }

  Future<void> openJournalFolder() async {
    if (!Platform.isWindows) return;
    final folder = directory;
    await folder.create(recursive: true);
    await Process.start('explorer.exe', <String>[folder.path], runInShell: false);
  }
}
