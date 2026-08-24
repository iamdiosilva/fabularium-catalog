import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tg/tg.dart' as tg;

class TelegramSocket extends tg.SocketAbstraction {
  TelegramSocket(this.socket)
      : _receiver = socket.asBroadcastStream();

  final Socket socket;

  final Stream<Uint8List> _receiver;

  @override
  Stream<Uint8List> get receiver => _receiver;

  @override
  Future<void> send(List<int> data) async {
    socket.add(data);

    await socket.flush();
  }

  Future<void> close() async {
    await socket.close();
  }
}