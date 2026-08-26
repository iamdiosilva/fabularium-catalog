import '../../../models/telegram_message.dart';
import '../domain/entities/telegram_catalog_entry.dart';

class TelegramCatalogCaptionParser {
  static final RegExp _packagePattern = RegExp(
    r'^\[FABULARIUM:([^\]]+)\]$',
  );

  TelegramCatalogEntry? parse(
    TelegramMessage message,
  ) {
    final media = message.media;

    if (media == null || !media.isPhoto) {
      return null;
    }

    final normalized = message.text.replaceAll(
      '\r\n',
      '\n',
    );

    final lines = normalized.split('\n');

    if (lines.isEmpty) {
      return null;
    }

    final packageMatch = _packagePattern.firstMatch(
      lines.first.trim(),
    );

    if (packageMatch == null) {
      return null;
    }

    final packageId =
        packageMatch.group(1)?.trim() ?? '';

    if (packageId.isEmpty) {
      return null;
    }

    String name = '';
    String studio = '';
    String category = '';
    String type = '';
    String scale = '';
    String height = '';
    String archiveSizeLabel = '';
    int? partCount;

    var partsLineIndex = -1;

    for (var index = 1;
        index < lines.length;
        index++) {
      final line = lines[index].trim();

      if (line.isEmpty) {
        continue;
      }

      if (name.isEmpty &&
          line.startsWith('🖼')) {
        name = line
            .replaceFirst(
              RegExp(r'^🖼\s*'),
              '',
            )
            .trim();
        continue;
      }

      final separator = line.indexOf(':');

      if (separator <= 0) {
        if (name.isEmpty) {
          name = line;
        }
        continue;
      }

      final key = line
          .substring(0, separator)
          .trim()
          .toLowerCase();

      final value = line
          .substring(separator + 1)
          .trim();

      switch (key) {
        case 'studio':
          studio = value;
          break;
        case 'category':
          category = value;
          break;
        case 'type':
          type = value;
          break;
        case 'scale':
          scale = value;
          break;
        case 'height':
          height = value;
          break;
        case 'archive':
          archiveSizeLabel = value;
          break;
        case 'parts':
          partCount = int.tryParse(value);
          partsLineIndex = index;
          break;
      }
    }

    final description = partsLineIndex >= 0
        ? lines
            .skip(partsLineIndex + 1)
            .join('\n')
            .trim()
        : '';

    return TelegramCatalogEntry(
      packageId: packageId,
      messageId: message.id,
      name: name.isEmpty
          ? 'Telegram Model'
          : name,
      studio: studio,
      category: category,
      type: type,
      scale: scale,
      height: height,
      archiveSizeLabel: archiveSizeLabel,
      partCount: partCount,
      description: description,
      publishedAt: message.date,
      coverMedia: media,
    );
  }
}
