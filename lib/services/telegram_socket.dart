import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tg/tg.dart' as tg;

class TelegramSocket extends tg.SocketAbstraction {
  TelegramSocket(this.socket)
      : _receiver = socket.asBroadcastStream();

  final Socket socket;

  final Stream<Uint8List> _receiver;

  /*
   * Fila de escrita.
   *
   * O tg.Client pode executar vários invoke()
   * ao mesmo tempo.
   *
   * Isso significa que vários socket.send()
   * podem chegar simultaneamente aqui.
   *
   * Dart Socket/IOSink não deve receber
   * add + flush concorrentes.
   *
   * Esta fila garante:
   *
   * send 1
   *   ↓
   * send 2
   *   ↓
   * send 3
   *
   * sempre nessa ordem.
   */
  Future<void> _writeTail =
      Future<void>.value();

  bool _isClosing = false;

  bool _isClosed = false;

  Completer<void>? _closeCompleter;

  @override
  Stream<Uint8List> get receiver =>
      _receiver;

  @override
  Future<void> send(
    List<int> data,
  ) async {
    if (_isClosing ||
        _isClosed) {
      throw StateError(
        'Telegram socket está fechado.',
      );
    }

    /*
     * Fazemos uma cópia.
     *
     * O pacote tg trabalha com buffers
     * que passam por criptografia.
     *
     * Não queremos que uma referência
     * externa seja modificada enquanto
     * aguarda sua vez na fila.
     */
    final bytes =
        Uint8List.fromList(
      data,
    );

    /*
     * Guarda o último trabalho que já
     * estava na fila.
     */
    final previous =
        _writeTail;

    /*
     * Representa nossa posição atual
     * na fila.
     */
    final turn =
        Completer<void>();

    /*
     * O próximo send() ficará esperando
     * este completer.
     */
    _writeTail =
        turn.future;

    /*
     * Esperamos todas as escritas anteriores.
     */
    await previous;

    try {
      if (_isClosed) {
        throw StateError(
          'Telegram socket está fechado.',
        );
      }

      socket.add(
        bytes,
      );

      /*
       * É importante aguardar o flush antes
       * de liberar a próxima mensagem.
       */
      await socket.flush();
    } finally {
      /*
       * Libera o próximo item da fila mesmo
       * se a escrita atual gerar exceção.
       *
       * Isso evita travar permanentemente
       * todos os próximos sends.
       */
      if (!turn.isCompleted) {
        turn.complete();
      }
    }
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    /*
     * Se outro ponto já iniciou o fechamento,
     * esperamos exatamente o mesmo processo.
     */
    if (_isClosing) {
      final closeCompleter =
          _closeCompleter;

      if (closeCompleter != null) {
        await closeCompleter.future;
      }

      return;
    }

    _isClosing = true;

    final closeCompleter =
        Completer<void>();

    _closeCompleter =
        closeCompleter;

    try {
      /*
       * Espera tudo que já entrou na fila
       * terminar antes de fechar o socket.
       */
      await _writeTail;

      try {
        await socket.flush();
      } catch (_) {
        /*
         * O socket pode já estar sendo
         * encerrado pelo sistema.
         */
      }

      try {
        await socket.close();
      } catch (_) {
        /*
         * Fechamento idempotente.
         */
      }
    } finally {
      _isClosed = true;

      _isClosing = false;

      if (!closeCompleter.isCompleted) {
        closeCompleter.complete();
      }
    }
  }
}