class TelegramMessage {
  final int id;
  final String text;
  final String sender;
  final DateTime? date;

  const TelegramMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.date,
  });
}