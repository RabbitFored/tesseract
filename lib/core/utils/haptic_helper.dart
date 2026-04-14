import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/settings_controller.dart';

/// Centralized haptic feedback helper that respects user settings.
class HapticHelper {
  HapticHelper(this._ref);

  final Ref _ref;

  bool get _isEnabled =>
      _ref.read(settingsControllerProvider).hapticsEnabled;

  /// Light impact - for subtle interactions (button taps, switches)
  Future<void> light() async {
    if (!_isEnabled) return;
    await HapticFeedback.lightImpact();
  }

  /// Medium impact - for standard interactions (download start/pause)
  Future<void> medium() async {
    if (!_isEnabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Heavy impact - for important actions (delete, cancel)
  Future<void> heavy() async {
    if (!_isEnabled) return;
    await HapticFeedback.heavyImpact();
  }

  /// Selection feedback - for scrolling through items, sliders
  Future<void> selection() async {
    if (!_isEnabled) return;
    await HapticFeedback.selectionClick();
  }

  /// Success feedback - for completed actions
  Future<void> success() async {
    if (!_isEnabled) return;
    // Double light tap for success feel
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.lightImpact();
  }

  /// Error feedback - for failed actions
  Future<void> error() async {
    if (!_isEnabled) return;
    // Triple medium tap for error feel
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.mediumImpact();
  }

  /// Long press feedback - for context menus, multi-select
  Future<void> longPress() async {
    if (!_isEnabled) return;
    await HapticFeedback.heavyImpact();
  }
}

/// Provider for haptic feedback helper
final hapticHelperProvider = Provider<HapticHelper>((ref) {
  return HapticHelper(ref);
});
