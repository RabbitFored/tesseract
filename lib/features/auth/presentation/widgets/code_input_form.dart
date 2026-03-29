import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OTP code input form shown during [AuthWaitCode].
class CodeInputForm extends StatefulWidget {
  const CodeInputForm({
    super.key,
    required this.phoneNumber,
    required this.codeLength,
    required this.codeType,
    required this.onSubmit,
  });

  final String phoneNumber;
  final int codeLength;
  final String codeType;
  final Future<void> Function(String code) onSubmit;

  @override
  State<CodeInputForm> createState() => _CodeInputFormState();
}

class _CodeInputFormState extends State<CodeInputForm> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_controller.text.trim());
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
          Text(
            'Enter the code',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a ${widget.codeLength}-digit code via ${widget.codeType} '
            'to ${widget.phoneNumber}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            maxLength: widget.codeLength,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 12,
              fontWeight: FontWeight.w600,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              hintText: '0' * widget.codeLength,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Code is required';
              }
              if (value.trim().length < widget.codeLength) {
                return 'Enter all ${widget.codeLength} digits';
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _handleSubmit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_submitting ? 'Verifying...' : 'Verify Code'),
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
