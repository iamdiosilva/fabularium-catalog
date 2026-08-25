import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PerformanceMonitor {
  PerformanceMonitor._();

  static final PerformanceMonitor instance =
      PerformanceMonitor._();

  bool _started = false;

  static const double _warningMilliseconds =
      24.0;

  void start() {
    if (_started) {
      return;
    }

    if (!kDebugMode &&
        !kProfileMode) {
      return;
    }

    _started = true;

    SchedulerBinding.instance
        .addTimingsCallback(
      _onTimings,
    );

    debugPrint(
      '[PERF] Performance monitor started.',
    );
  }

  void stop() {
    if (!_started) {
      return;
    }

    SchedulerBinding.instance
        .removeTimingsCallback(
      _onTimings,
    );

    _started = false;
  }

  void _onTimings(
    List<FrameTiming> timings,
  ) {
    for (final timing in timings) {
      final buildMs =
          timing.buildDuration
                  .inMicroseconds /
              1000.0;

      final rasterMs =
          timing.rasterDuration
                  .inMicroseconds /
              1000.0;

      final totalMs =
          timing.totalSpan
                  .inMicroseconds /
              1000.0;

      if (buildMs <
              _warningMilliseconds &&
          rasterMs <
              _warningMilliseconds &&
          totalMs <
              _warningMilliseconds) {
        continue;
      }

      final cause =
          _classify(
        buildMs,
        rasterMs,
      );

      debugPrint(
        '[PERF][JANK] '
        'build=${buildMs.toStringAsFixed(1)}ms | '
        'raster=${rasterMs.toStringAsFixed(1)}ms | '
        'total=${totalMs.toStringAsFixed(1)}ms | '
        'suspect=$cause',
      );
    }
  }

  String _classify(
    double buildMs,
    double rasterMs,
  ) {
    if (buildMs >
            _warningMilliseconds &&
        rasterMs >
            _warningMilliseconds) {
      return 'BUILD + RASTER';
    }

    if (buildMs >
        _warningMilliseconds) {
      return 'BUILD / MAIN ISOLATE';
    }

    if (rasterMs >
        _warningMilliseconds) {
      return 'RASTER / IMAGE / GPU';
    }

    return 'FRAME SCHEDULING';
  }
}