import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../models/catalog_model.dart';

class CatalogModelIdentityService {
  CatalogModelIdentityService._();
  static final CatalogModelIdentityService instance = CatalogModelIdentityService._();
  static const String configKey = 'modelId';

  Future<String> ensureModelId(CatalogModel model) async {
    final existing = _normalizeModelId(model.config[configKey]);
    if (existing != null) return existing;
    final configFile = File(p.join(model.folderPath, 'config.json'));
    if (!await configFile.exists()) {
      throw const CatalogModelIdentityException('The model config.json file was not found.');
    }
    Map<String, dynamic> config;
    try {
      final decoded = jsonDecode(await configFile.readAsString());
      if (decoded is! Map) throw const FormatException('config.json is not a JSON object.');
      config = Map<String, dynamic>.from(decoded);
    } catch (e) {
      throw CatalogModelIdentityException('Could not read model identity: $e');
    }
    final current = _normalizeModelId(config[configKey]);
    if (current != null) return current;
    final modelId = _createModelId();
    config[configKey] = modelId;
    final temp = File('${configFile.path}.tmp');
    try {
      const encoder = JsonEncoder.withIndent('  ');
      await temp.writeAsString(encoder.convert(config), flush: true);
      if (await configFile.exists()) await configFile.delete();
      await temp.rename(configFile.path);
    } catch (e) {
      try { if (await temp.exists()) await temp.delete(); } catch (_) {}
      throw CatalogModelIdentityException('Could not persist modelId in config.json: $e');
    }
    return modelId;
  }

  String? readModelId(CatalogModel model) => _normalizeModelId(model.config[configKey]);

  String? _normalizeModelId(dynamic value) {
    if (value == null) return null;
    final result = value.toString().trim();
    return result.isEmpty ? null : result;
  }

  String _createModelId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return 'fab-${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }
}

class CatalogModelIdentityException implements Exception {
  final String message;
  const CatalogModelIdentityException(this.message);
  @override
  String toString() => message;
}
