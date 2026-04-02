import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloader/data/download_manager.dart';

/// Dialog for adding a Telegram message link to the download queue.
///
/// Handles the following edge cases:
/// - Dialog dismissed while a request is in flight (`_cancelled` flag).
/// - Long-running or hanging requests via a 15-second timeout.
/// - User can abort via a Cancel button shown during loading.
class AddLinkDialog extends ConsumerStatefulWidget {
  const AddLinkDialog({super.key});

  @override
  ConsumerState<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends ConsumerState<AddLinkDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  /// Set to true in [dispose] so we can safely discard in-flight results.
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    // Auto-paste clipboard content if it looks like a Telegram link.
    _tryAutoPasteClipboard();
  }

  @override
  void dispose() {
    _cancelled = true;
    _controller.dispose();
    super.dispose();
  }

  /// Reads the clipboard and pre-fills the field if it contains a t.me link.
  Future<void> _tryAutoPasteClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || _cancelled) return;
      if (text.startsWith('https://t.me/') || text.startsWith('http://t.me/')) {
        _controller.text = text;
      }
    } catch (_) {
      // Clipboard read failure is non-critical — ignore silently.
    }
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    if (_isLoading) return; // Prevent double-submit.

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final manager = ref.read(downloadManagerProvider);

    String? error;
    try {
      // Enforce a 15-second client-side timeout so the dialog never hangs
      // indefinitely regardless of TDLib's internal 40s timeout.
      error = await manager.enqueueFromUrl(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => 'Request timed out. Please try again.',
      );
    } catch (e) {
      error = 'Unexpected error: $e';
    }

    // Guard: if the dialog was closed while the request was in-flight,
    // do not attempt to call setState or Navigator — the widget is gone.
    if (_cancelled || !mounted) return;

    if (error != null) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    } else {
      Navigator.of(context).pop(true);
    }
  }

  /// Cancels the in-flight request and closes the dialog.
  void _cancel() {
    // Mark as cancelled so any in-flight result is safely discarded.
    _cancelled = true;
    Navigator.of(context).pop(false);
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
            enabled: !_isLoading,
            decoration: InputDecoration(
              hintText: 'https://t.me/...',
              errorText: _error,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              // Paste button shortcut in the suffix.
              suffixIcon: !_isLoading
                  ? IconButton(
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      tooltip: 'Paste',
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (!mounted) return;
                        final text = data?.text?.trim() ?? '';
                        if (text.isNotEmpty) {
                          _controller.text = text;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: text.length),
                          );
                        }
                      },
                    )
                  : null,
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          // Loading progress indicator with hint.
          if (_isLoading) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fetching link info…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        // Cancel always available — closes the dialog cleanly even mid-request.
        TextButton(
          onPressed: _cancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
