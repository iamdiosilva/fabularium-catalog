import 'dart:async';

import 'package:flutter/material.dart';

import 'telegram_download_worker.dart';

class TelegramPerformanceCoordinator
    extends NavigatorObserver {
  TelegramPerformanceCoordinator._();

  static final TelegramPerformanceCoordinator instance =
      TelegramPerformanceCoordinator._();

  static const Duration _interactiveDuration =
      Duration(
    milliseconds: 1400,
  );

  Timer? _idleTimer;

  bool _interactive =
      false;

  bool get isInteractive =>
      _interactive;

  void noteInteraction() {
    _idleTimer?.cancel();

    _setInteractive(
      true,
    );

    _idleTimer =
        Timer(
      _interactiveDuration,
      () {
        _setInteractive(
          false,
        );
      },
    );
  }

  void _setInteractive(
    bool value,
  ) {
    if (_interactive ==
        value) {
      return;
    }

    _interactive =
        value;

    /*
     * Não inicia o worker se ele ainda
     * não existir.
     *
     * O TelegramDownloadWorker apenas guarda
     * o estado e o aplica quando iniciar.
     */
    TelegramDownloadWorker.instance
        .setInteractiveMode(
      value,
    );
  }

  @override
  void didPush(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    noteInteraction();

    super.didPush(
      route,
      previousRoute,
    );
  }

  @override
  void didPop(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    noteInteraction();

    super.didPop(
      route,
      previousRoute,
    );
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    noteInteraction();

    super.didReplace(
      newRoute:
          newRoute,
      oldRoute:
          oldRoute,
    );
  }

  @override
  void didRemove(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    noteInteraction();

    super.didRemove(
      route,
      previousRoute,
    );
  }

  void disposeCoordinator() {
    _idleTimer?.cancel();

    _idleTimer =
        null;

    _setInteractive(
      false,
    );
  }
}