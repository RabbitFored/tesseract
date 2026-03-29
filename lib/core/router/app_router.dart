import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';

/// Root router widget that switches between [AuthScreen] and [DashboardScreen]
/// based on the current [AuthFlowState].
class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    // Once authenticated, show the dashboard; otherwise show auth flow.
    if (authState is AuthReady) {
      return const DashboardScreen();
    }
    return const AuthScreen();
  }
}
