import 'package:flutter/material.dart';

/// 2FA password input form shown during [AuthWaitPassword].
class PasswordInputForm extends StatefulWidget {
  const PasswordInputForm({
    super.key,
    required this.passwordHint,
    required this.onSubmit,
  });

  final String passwordHint;
  final Future<void> Function(String password) onSubmit;

  @override
  State<PasswordInputForm> createState() => _PasswordInputFormState();
}

class _PasswordInputFormState extends State<PasswordInputForm> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_controller.text);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Icon ─────────────────────────────────────────────
          Icon(
            Icons.lock_outline_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),

          Text(
            'Two-Factor Authentication',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your account is protected with a cloud password.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.passwordHint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Hint: ${widget.passwordHint}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Password field ───────────────────────────────────
          TextFormField(
            controller: _controller,
            obscureText: _obscured,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Cloud password',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 24),

          // ── Submit ───────────────────────────────────────────
          FilledButton.icon(
            onPressed: _submitting ? null : _handleSubmit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_submitting ? 'Checking...' : 'Submit Password'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
