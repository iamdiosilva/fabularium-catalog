import 'telegram_media.dart';

class TelegramMessage {
  final int id;
  final String text;
  final String sender;
  final DateTime? date;
  final TelegramMedia? media;

  const TelegramMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.date,
    required this.media,
  });

  bool get hasMedia => media != null;
}
