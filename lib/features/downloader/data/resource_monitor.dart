import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../settings/data/settings_controller.dart';

/// Callback signature for resource constraint violations.
typedef ResourceCallback = void Function(String reason);

/// Monitors network connectivity and battery state.
/// Triggers pause/resume callbacks when conditions are violated or restored.
///
/// Runs in the MAIN isolate only. Does not touch TDLib or SQLite directly.
class ResourceMonitor {
  ResourceMonitor(this._ref);

  final Ref _ref;
  final _connectivity = Connectivity();
  final _battery = Battery();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<BatteryState>? _batterySub;

  ResourceCallback? onConstraintViolated;
  ResourceCallback? onConstraintRestored;

  bool _isPausedByResource = false;
  bool _isWifiConnected = true;
  bool _isBatteryLow = false;

  /// Whether downloads are currently paused due to resource constraints.
  bool get isPausedByResource => _isPausedByResource;

  // ── Lifecycle ────────────────────────────────────────────────

  Future<void> start() async {
    // Check initial state.
    await _checkConnectivity();
    await _checkBattery();

    // Subscribe to streams.
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    _batterySub = _battery.onBatteryStateChanged.listen((_) => _checkBattery());

    Log.info('ResourceMonitor started', tag: 'RES_MON');
  }

  void dispose() {
    _connSub?.cancel();
    _batterySub?.cancel();
  }

  // ── Connectivity ─────────────────────────────────────────────

  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _updateConnectivity(results);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _updateConnectivity(results);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.wifiOnly) {
      _isWifiConnected = true; // constraint disabled — always OK
      _evaluate();
      return;
    }

    _isWifiConnected = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);

    Log.info(
      'Connectivity: wifi=$_isWifiConnected (results=$results)',
      tag: 'RES_MON',
    );
    _evaluate();
  }

  // ── Battery ──────────────────────────────────────────────────

  Future<void> _checkBattery() async {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.pauseOnLowBattery) {
      _isBatteryLow = false; // constraint disabled
      _evaluate();
      return;
    }

    final level = await _battery.batteryLevel;
    _isBatteryLow = level < 15;

    Log.info(
      'Battery: level=$level%, low=$_isBatteryLow',
      tag: 'RES_MON',
    );
    _evaluate();
  }

  // ── Evaluation ───────────────────────────────────────────────

  void _evaluate() {
    final shouldPause = !_isWifiConnected || _isBatteryLow;

    if (shouldPause && !_isPausedByResource) {
      _isPausedByResource = true;
      final reason = !_isWifiConnected
          ? 'Wi-Fi disconnected (Wi-Fi Only mode enabled)'
          : 'Battery below 15% (Low Battery pause enabled)';
      Log.info('Constraint violated: $reason', tag: 'RES_MON');
      onConstraintViolated?.call(reason);
    } else if (!shouldPause && _isPausedByResource) {
      _isPausedByResource = false;
      Log.info('Constraints restored — resuming', tag: 'RES_MON');
      onConstraintRestored?.call('Conditions met — resuming downloads');
    }
  }

  /// Re-evaluate after settings change.
  void recheck() {
    _checkConnectivity();
    _checkBattery();
  }
}
