import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_package.dart';

typedef TelegramStoragePackageProgress =
    void Function(
  double progress,
  String stage,
);

class TelegramStoragePackager {
  TelegramStoragePackager._();

  static final TelegramStoragePackager
      instance =
      TelegramStoragePackager._();

  /*
   * Mesmo limite utilizado pelo upload.
   *
   * Mantemos margem segura abaixo dos
   * aproximadamente 2 GB.
   */
  static const int maxPartBytes =
      1900 * 1024 * 1024;

  /*
   * Buffer usado ao dividir arquivos.
   *
   * Nunca carregamos um ZIP gigante inteiro
   * na memória.
   */
  static const int _splitBufferBytes =
      8 * 1024 * 1024;

  // ============================================================
  // PREPARE FOLDER
  // ============================================================

  Future<TelegramStoragePackage>
      prepareFolder({
    required String folderPath,
    TelegramStoragePackageProgress?
        onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw const TelegramStoragePackagingException(
        'Telegram Storage packaging is currently supported only on Windows.',
      );
    }

    final sourceDirectory =
        Directory(
      folderPath,
    );

    if (!await sourceDirectory.exists()) {
      throw const TelegramStoragePackagingException(
        'The selected folder no longer exists.',
      );
    }

    final folderName =
        p.basename(
      sourceDirectory.path,
    );

    if (folderName.trim().isEmpty) {
      throw const TelegramStoragePackagingException(
        'Invalid source folder.',
      );
    }

    _report(
      onProgress,
      0,
      'Locating 7-Zip...',
    );

    final sevenZip =
        await _findSevenZip();

    if (sevenZip == null) {
      throw const TelegramStoragePackagingException(
        '7-Zip was not found. Install 7-Zip before creating storage packages.',
      );
    }

    _report(
      onProgress,
      0.02,
      'Scanning model folder...',
    );

    final sourceSize =
        await _calculateDirectorySize(
      sourceDirectory,
    );

    if (sourceSize <= 0) {
      throw const TelegramStoragePackagingException(
        'The selected folder contains no files.',
      );
    }

    final packageId =
        _createPackageId();

    final safeFolderName =
        _sanitizeName(
      folderName,
    );

    final stagingDirectory =
        await _createStagingDirectory(
      packageId,
    );

    final archiveFileName =
        '${safeFolderName}_$packageId.zip';

    final archiveFile =
        File(
      p.join(
        stagingDirectory.path,
        archiveFileName,
      ),
    );

    final createdAt =
        DateTime.now();

    try {
      // ========================================================
      // ZIP
      // ========================================================

      _report(
        onProgress,
        0.05,
        'Creating ZIP archive...',
      );

      await _createZip(
        sevenZip:
            sevenZip,
        sourceDirectory:
            sourceDirectory,
        destinationFile:
            archiveFile,
        onProgress:
            (
          value,
        ) {
          /*
           * Compressão ocupa aproximadamente
           * 5% -> 70% do progresso total.
           */
          final mapped =
              0.05 +
                  (
                    value * 0.65
                  );

          _report(
            onProgress,
            mapped,
            'Creating ZIP archive...',
          );
        },
      );

      if (!await archiveFile.exists()) {
        throw const TelegramStoragePackagingException(
          '7-Zip completed but the archive was not created.',
        );
      }

      final archiveSize =
          await archiveFile.length();

      if (archiveSize <= 0) {
        throw const TelegramStoragePackagingException(
          'The generated ZIP archive is empty.',
        );
      }

      // ========================================================
      // ARCHIVE SHA256
      // ========================================================

      _report(
        onProgress,
        0.72,
        'Calculating archive SHA-256...',
      );

      final archiveSha256 =
          await _calculateSha256(
        archiveFile,
      );

      final parts =
          <TelegramStoragePackagePart>[];

      // ========================================================
      // SINGLE FILE
      // ========================================================

      if (archiveSize <=
          maxPartBytes) {
        _report(
          onProgress,
          0.9,
          'Preparing package manifest...',
        );

        parts.add(
          TelegramStoragePackagePart(
            index:
                1,
            filePath:
                archiveFile.path,
            fileName:
                archiveFileName,
            size:
                archiveSize,
            sha256:
                archiveSha256,
          ),
        );
      }

      // ========================================================
      // SPLIT
      // ========================================================

      else {
        _report(
          onProgress,
          0.75,
          'Archive exceeds 1900 MB. Splitting...',
        );

        final splitParts =
            await _splitArchive(
          archiveFile:
              archiveFile,
          archiveSize:
              archiveSize,
          archiveFileName:
              archiveFileName,
          onProgress:
              (
            copied,
            total,
          ) {
            final ratio =
                total <= 0
                    ? 0.0
                    : copied /
                        total;

            /*
             * Split ocupa 75% -> 87%.
             */
            _report(
              onProgress,
              0.75 +
                  (
                    ratio *
                        0.12
                  ),
              'Splitting archive...',
            );
          },
        );

        _report(
          onProgress,
          0.88,
          'Calculating part checksums...',
        );

        for (int index = 0;
            index <
                splitParts.length;
            index++) {
          final file =
              splitParts[index];

          final hash =
              await _calculateSha256(
            file,
          );

          parts.add(
            TelegramStoragePackagePart(
              index:
                  index + 1,
              filePath:
                  file.path,
              fileName:
                  p.basename(
                file.path,
              ),
              size:
                  await file.length(),
              sha256:
                  hash,
            ),
          );

          final hashRatio =
              (
                index + 1
              ) /
                  splitParts.length;

          _report(
            onProgress,
            0.88 +
                (
                  hashRatio *
                      0.07
                ),
            'Calculating part checksums '
            '${index + 1}/${splitParts.length}...',
          );
        }

        /*
         * A partir daqui as partes são a
         * representação persistida do ZIP.
         *
         * O ZIP original já teve seu SHA-256
         * calculado e não é mais necessário.
         *
         * Removê-lo evita manter duas cópias
         * gigantes no staging.
         */
        await archiveFile.delete();
      }

      if (parts.isEmpty) {
        throw const TelegramStoragePackagingException(
          'No storage package parts were generated.',
        );
      }

      // ========================================================
      // MANIFEST
      // ========================================================

      _report(
        onProgress,
        0.96,
        'Writing manifest...',
      );

      final manifestFile =
          File(
        p.join(
          stagingDirectory.path,
          '${safeFolderName}_$packageId'
              '.fabmanifest.json',
        ),
      );

      final package =
          TelegramStoragePackage(
        packageId:
            packageId,
        sourceFolderName:
            folderName,
        sourceSize:
            sourceSize,
        archiveFileName:
            archiveFileName,
        archiveSize:
            archiveSize,
        archiveSha256:
            archiveSha256,
        stagingDirectoryPath:
            stagingDirectory.path,
        manifestPath:
            manifestFile.path,
        createdAt:
            createdAt,
        parts:
            parts,
      );

      await writeManifest(
        package,
      );

      _report(
        onProgress,
        1,
        'Package ready.',
      );

      return package;
    } catch (_) {
      /*
       * Não deixamos ZIPs ou partes gigantes
       * incompletos no disco caso a preparação
       * falhe.
       */
      try {
        if (await stagingDirectory.exists()) {
          await stagingDirectory.delete(
            recursive:
                true,
          );
        }
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // MANIFEST
  // ============================================================

  Future<void> writeManifest(
    TelegramStoragePackage package, {
    int? channelId,
    String? channelTitle,
    Map<int, int?> messageIds =
        const <int, int?>{},
  }) async {
    final file =
        File(
      package.manifestPath,
    );

    await file.parent.create(
      recursive:
          true,
    );

    final tempFile =
        File(
      '${file.path}.tmp',
    );

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await tempFile.writeAsString(
      encoder.convert(
        package.toManifestJson(
          channelId:
              channelId,
          channelTitle:
              channelTitle,
          messageIds:
              messageIds,
        ),
      ),
      flush:
          true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await tempFile.rename(
      file.path,
    );
  }

  // ============================================================
  // ZIP
  // ============================================================

  Future<void> _createZip({
    required String sevenZip,
    required Directory sourceDirectory,
    required File destinationFile,
    required void Function(
      double progress,
    )
        onProgress,
  }) async {
    final parent =
        sourceDirectory.parent;

    final sourceName =
        p.basename(
      sourceDirectory.path,
    );

    final process =
        await Process.start(
      sevenZip,
      <String>[
        'a',
        '-tzip',
        '-mx=5',
        '-y',
        '-bsp1',
        '-bb0',
        destinationFile.path,
        sourceName,
      ],
      workingDirectory:
          parent.path,
      runInShell:
          false,
    );

    final errorOutput =
        StringBuffer();

    final progressExpression =
        RegExp(
      r'(\d{1,3})%',
    );

    final stdoutFuture =
        process.stdout
            .transform(
              systemEncoding.decoder,
            )
            .listen(
              (
                output,
              ) {
                final matches =
                    progressExpression
                        .allMatches(
                  output,
                );

                for (final match
                    in matches) {
                  final percentage =
                      int.tryParse(
                    match.group(
                          1,
                        ) ??
                        '',
                  );

                  if (percentage ==
                      null) {
                    continue;
                  }

                  onProgress(
                    (
                      percentage /
                          100
                    ).clamp(
                      0.0,
                      1.0,
                    ),
                  );
                }
              },
            )
            .asFuture<void>();

    final stderrFuture =
        process.stderr
            .transform(
              systemEncoding.decoder,
            )
            .listen(
              (
                output,
              ) {
                errorOutput.write(
                  output,
                );
              },
            )
            .asFuture<void>();

    final exitCode =
        await process.exitCode;

    await Future.wait(
      <Future<void>>[
        stdoutFuture,
        stderrFuture,
      ],
    );

    if (exitCode != 0) {
      final error =
          errorOutput
              .toString()
              .trim();

      throw TelegramStoragePackagingException(
        error.isEmpty
            ? '7-Zip could not create the archive. '
                'Exit code: $exitCode.'
            : '7-Zip could not create the archive:\n$error',
      );
    }

    onProgress(
      1,
    );
  }

  // ============================================================
  // SPLIT ARCHIVE
  // ============================================================

  Future<List<File>> _splitArchive({
    required File archiveFile,
    required int archiveSize,
    required String archiveFileName,
    required void Function(
      int copied,
      int total,
    )
        onProgress,
  }) async {
    final parts =
        <File>[];

    RandomAccessFile? input;

    try {
      input =
          await archiveFile.open(
        mode:
            FileMode.read,
      );

      int totalCopied =
          0;

      int partIndex =
          1;

      while (totalCopied <
          archiveSize) {
        final partName =
            '$archiveFileName'
            '.part'
            '${partIndex.toString().padLeft(3, '0')}';

        final partFile =
            File(
          p.join(
            archiveFile.parent.path,
            partName,
          ),
        );

        RandomAccessFile? output;

        try {
          output =
              await partFile.open(
            mode:
                FileMode.write,
          );

          final remainingArchive =
              archiveSize -
                  totalCopied;

          final targetPartSize =
              min(
            maxPartBytes,
            remainingArchive,
          );

          int writtenToPart =
              0;

          while (writtenToPart <
              targetPartSize) {
            final remainingPart =
                targetPartSize -
                    writtenToPart;

            final readLength =
                min(
              _splitBufferBytes,
              remainingPart,
            );

            final bytes =
                await input.read(
              readLength,
            );

            if (bytes.isEmpty) {
              throw const TelegramStoragePackagingException(
                'Unexpected end of ZIP while splitting the archive.',
              );
            }

            await output.writeFrom(
              bytes,
            );

            writtenToPart +=
                bytes.length;

            totalCopied +=
                bytes.length;

            onProgress(
              totalCopied,
              archiveSize,
            );
          }

          await output.flush();
        } finally {
          try {
            await output?.close();
          } catch (_) {}
        }

        final actualLength =
            await partFile.length();

        if (actualLength <= 0 ||
            actualLength >
                maxPartBytes) {
          throw TelegramStoragePackagingException(
            'Invalid generated storage part: '
            '${partFile.path}',
          );
        }

        parts.add(
          partFile,
        );

        partIndex++;
      }
    } finally {
      try {
        await input?.close();
      } catch (_) {}
    }

    return parts;
  }

  // ============================================================
  // SHA-256
  // ============================================================

  Future<String> _calculateSha256(
    File file,
  ) async {
    /*
     * Evitamos adicionar uma dependência só
     * para hashing neste momento.
     *
     * certutil faz parte do Windows e processa
     * o arquivo externamente, portanto não
     * bloqueamos o isolate da interface com
     * hashing de arquivos de vários gigabytes.
     */
    final result =
        await Process.run(
      'certutil',
      <String>[
        '-hashfile',
        file.path,
        'SHA256',
      ],
      runInShell:
          false,
    );

    if (result.exitCode != 0) {
      throw TelegramStoragePackagingException(
        'Could not calculate SHA-256 for '
        '${file.path}.',
      );
    }

    final output =
        result.stdout.toString();

    final lines =
        output.split(
      RegExp(
        r'[\r\n]+',
      ),
    );

    final hashPattern =
        RegExp(
      r'^[0-9a-fA-F]{64}$',
    );

    for (final line
        in lines) {
      final normalized =
          line.replaceAll(
        RegExp(
          r'\s+',
        ),
        '',
      );

      if (hashPattern.hasMatch(
        normalized,
      )) {
        return normalized
            .toLowerCase();
      }
    }

    throw TelegramStoragePackagingException(
      'Windows returned an invalid SHA-256 '
      'for ${file.path}.',
    );
  }

  // ============================================================
  // DIRECTORY SIZE
  // ============================================================

  Future<int> _calculateDirectorySize(
    Directory directory,
  ) async {
    int size =
        0;

    await for (final entity
        in directory.list(
      recursive:
          true,
      followLinks:
          false,
    )) {
      if (entity is! File) {
        continue;
      }

      try {
        size +=
            await entity.length();
      } catch (_) {
        /*
         * Um arquivo inacessível será
         * percebido também pelo 7-Zip.
         */
      }
    }

    return size;
  }

  // ============================================================
  // STAGING
  // ============================================================

  Future<Directory>
      _createStagingDirectory(
    String packageId,
  ) async {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData != null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        'storage_staging',
        packageId,
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  Future<void> deletePackage(
    TelegramStoragePackage package,
  ) async {
    final directory =
        Directory(
      package.stagingDirectoryPath,
    );

    try {
      if (await directory.exists()) {
        await directory.delete(
          recursive:
              true,
        );
      }
    } catch (e) {
      throw TelegramStoragePackagingException(
        'Could not delete storage staging files: $e',
      );
    }
  }

  Future<void> openPackageFolder(
    TelegramStoragePackage package,
  ) async {
    if (!Platform.isWindows) {
      return;
    }

    final directory =
        Directory(
      package.stagingDirectoryPath,
    );

    if (!await directory.exists()) {
      throw const TelegramStoragePackagingException(
        'The package staging folder no longer exists.',
      );
    }

    await Process.start(
      'explorer.exe',
      <String>[
        directory.path,
      ],
      runInShell:
          false,
    );
  }

  // ============================================================
  // 7-ZIP
  // ============================================================

  Future<String?> _findSevenZip() async {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final possiblePaths =
        <String>[
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
      r'C:\7-Zip\7z.exe',
      if (localAppData != null)
        p.join(
          localAppData,
          '7-Zip',
          '7z.exe',
        ),
    ];

    for (final path
        in possiblePaths) {
      final file =
          File(
        path,
      );

      if (await file.exists()) {
        return file.path;
      }
    }

    try {
      final result =
          await Process.run(
        'where',
        <String>[
          '7z.exe',
        ],
        runInShell:
            true,
      );

      if (result.exitCode == 0) {
        final output =
            result.stdout
                .toString()
                .trim();

        final paths =
            output
                .split(
                  RegExp(
                    r'[\r\n]+',
                  ),
                )
                .where(
                  (value) =>
                      value
                          .trim()
                          .isNotEmpty,
                )
                .toList();

        if (paths.isNotEmpty) {
          return paths.first
              .trim();
        }
      }
    } catch (_) {}

    return null;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _createPackageId() {
    final now =
        DateTime.now()
            .toUtc();

    final timestamp =
        now
            .millisecondsSinceEpoch
            .toRadixString(
              16,
            );

    final random =
        Random.secure()
            .nextInt(
              0x7fffffff,
            )
            .toRadixString(
              16,
            )
            .padLeft(
              8,
              '0',
            );

    return '${timestamp}_$random';
  }

  String _sanitizeName(
    String value,
  ) {
    final sanitized =
        value
            .replaceAll(
              RegExp(
                r'[<>:"/\\|?*]',
              ),
              '_',
            )
            .trim();

    if (sanitized.isEmpty) {
      return 'fabularium_model';
    }

    return sanitized;
  }

  void _report(
    TelegramStoragePackageProgress?
        callback,
    double progress,
    String stage,
  ) {
    callback?.call(
      progress.clamp(
        0.0,
        1.0,
      ),
      stage,
    );
  }
}

class TelegramStoragePackagingException
    implements Exception {
  final String message;

  const TelegramStoragePackagingException(
    this.message,
  );

  @override
  String toString() =>
      message;
}