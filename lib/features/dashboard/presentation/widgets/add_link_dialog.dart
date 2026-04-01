import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloader/data/download_manager.dart';

class AddLinkDialog extends ConsumerStatefulWidget {
  const AddLinkDialog({super.key});

  @override
  ConsumerState<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends ConsumerState<AddLinkDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final manager = ref.read(downloadManagerProvider);
    final error = await manager.enqueueFromUrl(url);

    if (mounted) {
      if (error != null) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add from Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Paste a public or private Telegram message link to download its attached file.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'https://t.me/...',
              errorText: _error,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
