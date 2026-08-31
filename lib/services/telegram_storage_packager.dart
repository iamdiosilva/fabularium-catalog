import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../models/telegram_storage_package.dart';

typedef TelegramStoragePackageProgress = void Function(double progress, String stage);

class TelegramStoragePackager {
  TelegramStoragePackager._();
  static final TelegramStoragePackager instance = TelegramStoragePackager._();
  static const int maxPartBytes = 1024 * 1024 * 1024;
  static const int _splitBufferBytes = 8 * 1024 * 1024;
  static const int maxGalleryImages = 10;

  Future<TelegramStoragePackage> prepareFolder({required String folderPath, TelegramStoragePackageProgress? onProgress}) async {
    if (!Platform.isWindows) throw const TelegramStoragePackagingException('Telegram Storage packaging is currently supported only on Windows.');
    final sourceDirectory = Directory(folderPath);
    if (!await sourceDirectory.exists()) throw const TelegramStoragePackagingException('The selected folder no longer exists.');
    final folderName = p.basename(sourceDirectory.path);
    if (folderName.trim().isEmpty) throw const TelegramStoragePackagingException('Invalid source folder.');
    _report(onProgress,0,'Locating 7-Zip...');
    final sevenZip = await _findSevenZip();
    if (sevenZip == null) throw const TelegramStoragePackagingException('7-Zip was not found. Install 7-Zip before creating storage packages.');
    _report(onProgress,0.01,'Reading catalog information...');
    final catalog = await _readCatalogInfo(sourceDirectory, folderName);
    _report(onProgress,0.02,'Scanning model folder...');
    final sourceSize = await _calculateDirectorySize(sourceDirectory);
    if (sourceSize <= 0) throw const TelegramStoragePackagingException('The selected folder contains no files.');
    final packageId = _createPackageId();
    final safeFolderName = _sanitizeName(catalog.name);
    final staging = await _createStagingDirectory(packageId);
    final archiveFileName = '${safeFolderName}_$packageId.zip';
    final archiveFile = File(p.join(staging.path, archiveFileName));
    final createdAt = DateTime.now();
    try {
      _report(onProgress,0.05,'Creating ZIP archive...');
      await _createZip(sevenZip:sevenZip,sourceDirectory:sourceDirectory,destinationFile:archiveFile,onProgress:(value)=>_report(onProgress,0.05+value*0.65,'Creating ZIP archive...'));
      if (!await archiveFile.exists()) throw const TelegramStoragePackagingException('7-Zip completed but the archive was not created.');
      final archiveSize = await archiveFile.length();
      if (archiveSize <= 0) throw const TelegramStoragePackagingException('The generated ZIP archive is empty.');
      _report(onProgress,0.72,'Calculating archive SHA-256...');
      final archiveSha256 = await _calculateSha256(archiveFile);
      final parts = <TelegramStoragePackagePart>[];
      if (archiveSize <= maxPartBytes) {
        parts.add(TelegramStoragePackagePart(index:1,filePath:archiveFile.path,fileName:archiveFileName,size:archiveSize,sha256:archiveSha256));
      } else {
        _report(onProgress,0.75,'Archive exceeds 1 GB. Splitting...');
        final splitParts = await _splitArchive(archiveFile:archiveFile,archiveSize:archiveSize,archiveFileName:archiveFileName,onProgress:(copied,total)=>_report(onProgress,0.75+(total<=0?0:copied/total)*0.12,'Splitting archive...'));
        _report(onProgress,0.88,'Calculating part checksums...');
        for (var i=0;i<splitParts.length;i++) {
          final file=splitParts[i];
          parts.add(TelegramStoragePackagePart(index:i+1,filePath:file.path,fileName:p.basename(file.path),size:await file.length(),sha256:await _calculateSha256(file)));
          _report(onProgress,0.88+((i+1)/splitParts.length)*0.07,'Calculating part checksums ${i+1}/${splitParts.length}...');
        }
        await archiveFile.delete();
      }
      if (parts.isEmpty) throw const TelegramStoragePackagingException('No storage package parts were generated.');
      _report(onProgress,0.96,'Writing manifest...');
      final manifestFile=File(p.join(staging.path,'${safeFolderName}_$packageId.fabmanifest.json'));
      final package=TelegramStoragePackage(packageId:packageId,sourceFolderName:folderName,sourceFolderPath:sourceDirectory.path,sourceSize:sourceSize,archiveFileName:archiveFileName,archiveSize:archiveSize,archiveSha256:archiveSha256,stagingDirectoryPath:staging.path,manifestPath:manifestFile.path,createdAt:createdAt,parts:parts,catalog:catalog);
      await writeManifest(package);
      _report(onProgress,1,'Package ready.');
      return package;
    } catch (_) {
      try { if(await staging.exists()) await staging.delete(recursive:true); } catch (_) {}
      rethrow;
    }
  }

  Future<TelegramStorageCatalogInfo> _readCatalogInfo(Directory directory,String fallbackName) async {
    final configFile=File(p.join(directory.path,'config.json')); Map<String,dynamic> config={};
    try { if(await configFile.exists()){final decoded=jsonDecode(await configFile.readAsString()); if(decoded is Map) config=Map<String,dynamic>.from(decoded);} } catch (_) {}
    final gallery=await _findGalleryImages(directory); final fallbackStudio=p.basename(directory.parent.path);
    return TelegramStorageCatalogInfo(
      modelId:_readString(config['modelId']) ?? _readString(config['id']) ?? '',
      name:_readString(config['name']) ?? fallbackName,
      studio:_readString(config['studio']) ?? _readString(config['manufacturer']) ?? fallbackStudio,
      category:_readString(config['category']), type:_readString(config['type']), scale:_readString(config['scale']), height:_readString(config['height']), description:_readString(config['description']), tags:_readTags(config['tags']), galleryImagePaths:gallery,
    );
  }
  String? _readString(dynamic value){if(value==null)return null;final text=value.toString().trim();return text.isEmpty?null:text;}
  List<String> _readTags(dynamic value)=>value is List?value.map((e)=>e.toString().trim()).where((e)=>e.isNotEmpty).toList():<String>[];

  Future<List<String>> _findGalleryImages(Directory directory) async {
    final files=<File>[];
    await for(final entity in directory.list(recursive:true,followLinks:false)){
      if(entity is! File)continue; final ext=p.extension(entity.path).toLowerCase(); if(ext=='.jpg'||ext=='.jpeg'||ext=='.png')files.add(entity);
    }
    files.sort((a,b){final pa=_galleryPriority(directory,a),pb=_galleryPriority(directory,b);return pa!=pb?pa.compareTo(pb):a.path.toLowerCase().compareTo(b.path.toLowerCase());});
    return files.take(maxGalleryImages).map((e)=>e.path).toList();
  }
  int _galleryPriority(Directory root, File file) {
    final relative = p.relative(file.path, from: root.path);
    final name = p.basenameWithoutExtension(file.path).toLowerCase();
    var priority = 50;

    if (name.contains('cover')) {
      priority = 0;
    } else if (name.contains('main')) {
      priority = 1;
    } else if (name.contains('preview')) {
      priority = 2;
    } else if (name.contains('render')) {
      priority = 3;
    }

    final depth = max(0, p.split(relative).length - 1);
    return priority * 100 + depth;
  }

  Future<void> writeManifest(TelegramStoragePackage package,{int? channelId,String? channelTitle}) async {
    final file=File(package.manifestPath);await file.parent.create(recursive:true);final tmp=File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(package.toManifestJson(channelId:channelId,channelTitle:channelTitle)),flush:true);
    if(await file.exists())await file.delete();await tmp.rename(file.path);
  }

  Future<void> _createZip({required String sevenZip,required Directory sourceDirectory,required File destinationFile,required void Function(double) onProgress}) async {
    final process=await Process.start(sevenZip,<String>['a','-tzip','-mx=5','-y','-bsp1','-bb0',destinationFile.path,p.basename(sourceDirectory.path)],workingDirectory:sourceDirectory.parent.path,runInShell:false);
    final errors=StringBuffer();final expr=RegExp(r'(\d{1,3})%');
    final out=process.stdout.transform(systemEncoding.decoder).listen((text){for(final m in expr.allMatches(text)){final v=int.tryParse(m.group(1)??'');if(v!=null)onProgress((v/100).clamp(0.0,1.0));}}).asFuture<void>();
    final err=process.stderr.transform(systemEncoding.decoder).listen(errors.write).asFuture<void>(); final exit=await process.exitCode;await Future.wait([out,err]);
    if(exit!=0)throw TelegramStoragePackagingException(errors.toString().trim().isEmpty?'7-Zip could not create the archive. Exit code: $exit.':'7-Zip could not create the archive:\n${errors.toString().trim()}'); onProgress(1);
  }

  Future<List<File>> _splitArchive({required File archiveFile,required int archiveSize,required String archiveFileName,required void Function(int,int) onProgress}) async {
    final parts=<File>[]; RandomAccessFile? input;
    try { input=await archiveFile.open(mode:FileMode.read);int total=0,index=1;while(total<archiveSize){final partFile=File(p.join(archiveFile.parent.path,'$archiveFileName.part${index.toString().padLeft(3,'0')}'));RandomAccessFile? output;try{output=await partFile.open(mode:FileMode.write);final target=min(maxPartBytes,archiveSize-total);int written=0;while(written<target){final bytes=await input.read(min(_splitBufferBytes,target-written));if(bytes.isEmpty)throw const TelegramStoragePackagingException('Unexpected end of ZIP while splitting the archive.');await output.writeFrom(bytes);written+=bytes.length;total+=bytes.length;onProgress(total,archiveSize);}await output.flush();}finally{try{await output?.close();}catch(_){}}final len=await partFile.length();if(len<=0||len>maxPartBytes)throw TelegramStoragePackagingException('Invalid generated storage part: ${partFile.path}');parts.add(partFile);index++;}} finally {try{await input?.close();}catch(_){}} return parts;
  }

  Future<String> _calculateSha256(File file) async {final r=await Process.run('certutil',['-hashfile',file.path,'SHA256'],runInShell:false);if(r.exitCode!=0)throw TelegramStoragePackagingException('Could not calculate SHA-256 for ${file.path}.');for(final line in r.stdout.toString().split(RegExp(r'[\r\n]+'))){final n=line.replaceAll(RegExp(r'\s+'),'');if(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(n))return n.toLowerCase();}throw TelegramStoragePackagingException('Windows returned an invalid SHA-256 for ${file.path}.');}
  Future<int> _calculateDirectorySize(Directory directory) async {int size=0;await for(final entity in directory.list(recursive:true,followLinks:false)){if(entity is File){try{size+=await entity.length();}catch(_){}}}return size;}
  Future<Directory> _createStagingDirectory(String packageId) async {final base=Platform.environment['LOCALAPPDATA'];final dir=Directory(p.join(base!=null&&base.isNotEmpty?base:Directory.systemTemp.path,'Fabularium','Telegram','storage_staging',packageId));await dir.create(recursive:true);return dir;}
  Future<void> deletePackage(TelegramStoragePackage package) async {final dir=Directory(package.stagingDirectoryPath);try{if(await dir.exists())await dir.delete(recursive:true);}catch(e){throw TelegramStoragePackagingException('Could not delete storage staging files: $e');}}
  Future<void> openPackageFolder(TelegramStoragePackage package) async {if(!Platform.isWindows)return;final dir=Directory(package.stagingDirectoryPath);if(!await dir.exists())throw const TelegramStoragePackagingException('The package staging folder no longer exists.');await Process.start('explorer.exe',[dir.path],runInShell:false);}
  Future<String?> _findSevenZip() async {final local=Platform.environment['LOCALAPPDATA'];for(final path in <String>[r'C:\Program Files\7-Zip\7z.exe',r'C:\Program Files (x86)\7-Zip\7z.exe',r'C:\7-Zip\7z.exe',if(local!=null)p.join(local,'7-Zip','7z.exe')]){if(await File(path).exists())return path;}try{final r=await Process.run('where',['7z.exe'],runInShell:true);if(r.exitCode==0){final paths=r.stdout.toString().trim().split(RegExp(r'[\r\n]+')).where((e)=>e.trim().isNotEmpty).toList();if(paths.isNotEmpty)return paths.first.trim();}}catch(_){}return null;}
  String _createPackageId(){final ts=DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(16);final rnd=Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8,'0');return '${ts}_$rnd';}
  String _sanitizeName(String value){final s=value.replaceAll(RegExp(r'[<>:"/\\|?*]'),'_').trim();return s.isEmpty?'fabularium_model':s;}
  void _report(TelegramStoragePackageProgress? callback,double progress,String stage)=>callback?.call(progress.clamp(0.0,1.0).toDouble(),stage);
}

class TelegramStoragePackagingException implements Exception {final String message;const TelegramStoragePackagingException(this.message);@override String toString()=>message;}
