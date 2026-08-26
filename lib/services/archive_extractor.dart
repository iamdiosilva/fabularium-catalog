import 'dart:io';
import 'package:path/path.dart' as p;

class ArchiveExtractor {
  Future<Directory> extract({
    required File archiveFile,
    required String studioName,
    required String modelName,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('A extração de arquivos ZIP/RAR atualmente é suportada apenas no Windows.');
    }
    final sevenZip = await _findSevenZip();
    if (sevenZip == null) {
      throw Exception('O 7-Zip não foi encontrado no computador.\n\nInstale o 7-Zip para poder extrair arquivos ZIP e RAR.');
    }
    final downloadsDirectory = await _getDownloadsDirectory();
    final modelDirectory = Directory(p.join(
      downloadsDirectory.path,
      'Fabularium',
      _sanitizeName(studioName),
      _sanitizeName(modelName),
    ));
    await modelDirectory.create(recursive: true);
    final archiveName = p.basenameWithoutExtension(archiveFile.path);
    final archiveDirectory = Directory(p.join(modelDirectory.path, _sanitizeName(archiveName)));
    await archiveDirectory.create(recursive: true);
    final result = await Process.run(
      sevenZip,
      ['x', archiveFile.path, '-o${archiveDirectory.path}', '-y'],
      runInShell: false,
    );
    if (result.exitCode != 0) throw Exception(_buildExtractionError(result));
    return archiveDirectory;
  }

  Future<List<Directory>> extractAll({
    required List<File> archiveFiles,
    required String studioName,
    required String modelName,
    void Function(int current, int total)? onProgress,
  }) async {
    final result = <Directory>[];
    for (var i = 0; i < archiveFiles.length; i++) {
      result.add(await extract(
        archiveFile: archiveFiles[i],
        studioName: studioName,
        modelName: modelName,
      ));
      onProgress?.call(i + 1, archiveFiles.length);
    }
    return result;
  }

  Future<String?> _findSevenZip() async {
    final paths = <String>[
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
      r'C:\7-Zip\7z.exe',
    ];
    for (final path in paths) {
      if (await File(path).exists()) return path;
    }
    try {
      final result = await Process.run('where', ['7z.exe'], runInShell: true);
      if (result.exitCode == 0) {
        final candidates = result.stdout.toString().trim().split(RegExp(r'[\r\n]+'))
            .where((item) => item.trim().isNotEmpty).toList();
        if (candidates.isNotEmpty) return candidates.first.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _getDownloadsDirectory() async {
    final profile = Platform.environment['USERPROFILE'];
    if (profile == null || profile.isEmpty) {
      throw Exception('Não foi possível localizar a pasta do usuário.');
    }
    final downloads = Directory(p.join(profile, 'Downloads'));
    await downloads.create(recursive: true);
    return downloads;
  }

  String _sanitizeName(String value) =>
      value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  String _buildExtractionError(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    if (stderr.isNotEmpty) return 'Erro ao extrair o arquivo:\n$stderr';
    if (stdout.isNotEmpty) return 'Erro ao extrair o arquivo:\n$stdout';
    return 'Não foi possível extrair o arquivo.';
  }
}
