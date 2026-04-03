import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../data/auth_controller.dart';
import '../domain/auth_state.dart';
import 'widgets/code_input_form.dart';
import 'widgets/password_input_form.dart';
import 'widgets/phone_input_form.dart';

/// The root auth screen that dynamically renders the correct input form
/// based on the current [AuthFlowState].
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    // Show error via SnackBar and revert to previous state.
    ref.listen<AuthFlowState>(authControllerProvider, (prev, next) {
      if (next is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: theme.colorScheme.onError,
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).clearError(),
            ),
          ),
        );
        // Auto-clear error so the form becomes usable again.
        Future.microtask(
          () => ref.read(authControllerProvider.notifier).clearError(),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo / branding ─────────────────────────────
                _BrandingHeader(theme: theme),
                const SizedBox(height: 48),

                // ── Dynamic form ────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildForm(authState, theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AuthFlowState authState, ThemeData theme) {
    return switch (authState) {
      AuthLoading() => const _LoadingIndicator(label: 'Connecting to Telegram...'),
      AuthWaitPhoneNumber() => PhoneInputForm(
          key: const ValueKey('phone'),
          onSubmit: ref.read(authControllerProvider.notifier).submitPhoneNumber,
        ),
      AuthWaitCode(phoneNumber: final phone, codeLength: final len, codeType: final type) =>
        CodeInputForm(
          key: const ValueKey('code'),
          phoneNumber: phone,
          codeLength: len,
          codeType: type,
          onSubmit: ref.read(authControllerProvider.notifier).submitCode,
        ),
      AuthWaitPassword(passwordHint: final hint) => PasswordInputForm(
          key: const ValueKey('password'),
          passwordHint: hint,
          onSubmit: ref.read(authControllerProvider.notifier).submitPassword,
        ),
      AuthReady() => const _LoadingIndicator(label: 'Authenticated! Redirecting...'),
      AuthError(previousState: final prev) => _buildForm(prev, theme),
    };
  }
}

// ── Private helper widgets ──────────────────────────────────────

class _BrandingHeader extends StatelessWidget {
  const _BrandingHeader({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.cloud_download_rounded,
            size: 40,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppConstants.appName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in with your Telegram account',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
