import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../settings/data/settings_controller.dart';

/// Callback signature for resource constraint violations.
typedef ResourceCallback = void Function(String reason);

/// Monitors network connectivity, battery state, thermal state, and schedule.
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
  Timer? _scheduleTimer;

  ResourceCallback? onConstraintViolated;
  ResourceCallback? onConstraintRestored;

  bool _isPausedByResource = false;
  bool _isWifiConnected = true;
  bool _isBatteryLow = false;
  bool _isCharging = false;
  bool _isHighThermal = false;
  bool _isOutsideSchedule = false;

  /// Whether downloads are currently paused due to resource constraints.
  bool get isPausedByResource => _isPausedByResource;

  // ── Lifecycle ────────────────────────────────────────────────

  Future<void> start() async {
    await _checkConnectivity();
    await _checkBattery();
    _checkSchedule();

    _connSub = _connectivity.onConnectivityChanged
        .listen(_onConnectivityChanged);
    _batterySub =
        _battery.onBatteryStateChanged.listen(_onBatteryStateChanged);

    // Re-evaluate schedule every minute.
    _scheduleTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkSchedule(),
    );

    Log.info('ResourceMonitor started', tag: 'RES_MON');
  }

  void dispose() {
    _connSub?.cancel();
    _batterySub?.cancel();
    _scheduleTimer?.cancel();
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
      _isWifiConnected = true;
      _evaluate();
      return;
    }

    // Allow cellular for small files if configured.
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

    // Check charging state.
    final state = await _battery.batteryState;
    _isCharging = state == BatteryState.charging ||
        state == BatteryState.full;

    // Check battery level.
    if (settings.pauseOnLowBattery) {
      final level = await _battery.batteryLevel;
      _isBatteryLow = level < settings.lowBatteryThresholdPct;
      Log.info(
        'Battery: level=$level%, low=$_isBatteryLow, charging=$_isCharging',
        tag: 'RES_MON',
      );
    } else {
      _isBatteryLow = false;
    }

    _evaluate();
  }

  void _onBatteryStateChanged(BatteryState state) {
    _isCharging = state == BatteryState.charging || state == BatteryState.full;
    _checkBattery();
  }

  // ── Thermal ──────────────────────────────────────────────────

  /// Called externally when thermal state changes (e.g. from platform channel).
  void reportThermalState(bool isHigh) {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.pauseOnHighThermal) {
      _isHighThermal = false;
    } else {
      _isHighThermal = isHigh;
    }
    Log.info('Thermal: high=$_isHighThermal', tag: 'RES_MON');
    _evaluate();
  }

  // ── Schedule ─────────────────────────────────────────────────

  void _checkSchedule() {
    final settings = _ref.read(settingsControllerProvider);
    _isOutsideSchedule =
        settings.downloadOnlyOnSchedule && !settings.isWithinSchedule;
    _evaluate();
  }

  // ── Evaluation ───────────────────────────────────────────────

  void _evaluate() {
    final settings = _ref.read(settingsControllerProvider);

    final chargingViolation =
        settings.chargingOnlyMode && !_isCharging;

    final shouldPause = !_isWifiConnected ||
        _isBatteryLow ||
        _isHighThermal ||
        _isOutsideSchedule ||
        chargingViolation;

    if (shouldPause && !_isPausedByResource) {
      _isPausedByResource = true;
      final reason = _violationReason(settings.chargingOnlyMode);
      Log.info('Constraint violated: $reason', tag: 'RES_MON');
      onConstraintViolated?.call(reason);
    } else if (!shouldPause && _isPausedByResource) {
      _isPausedByResource = false;
      Log.info('Constraints restored — resuming', tag: 'RES_MON');
      onConstraintRestored?.call('Conditions met — resuming downloads');
    }
  }

  String _violationReason(bool chargingOnly) {
    if (!_isWifiConnected) return 'Wi-Fi disconnected (Wi-Fi Only mode)';
    if (_isBatteryLow) return 'Battery below threshold';
    if (_isHighThermal) return 'Device temperature too high';
    if (_isOutsideSchedule) return 'Outside scheduled download window';
    if (chargingOnly && !_isCharging) return 'Not charging (Charging Only mode)';
    return 'Resource constraint';
  }

  /// Re-evaluate after settings change.
  void recheck() {
    _checkConnectivity();
    _checkBattery();
    _checkSchedule();
  }
}
