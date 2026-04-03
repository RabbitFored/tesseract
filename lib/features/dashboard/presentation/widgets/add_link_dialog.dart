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
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_isLoading) return; // Prevent double-submit.

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final manager = ref.read(downloadManagerProvider);

    // Parse multiple links based on whitespace, commas, or newlines
    final urls = text.split(RegExp(r'[\s,\n]+')).where((u) => u.isNotEmpty).toList();

    int successCount = 0;
    int failCount = 0;
    String? firstError;

    for (final url in urls) {
      try {
        final error = await manager.enqueueFromUrl(url).timeout(
          const Duration(seconds: 15),
          onTimeout: () => 'Request timed out for $url',
        );
        if (error != null) {
          failCount++;
          firstError ??= error;
        } else {
          successCount++;
        }
      } catch (e) {
        failCount++;
        firstError ??= 'Unexpected error: $e';
      }

      if (_cancelled || !mounted) return;
    }

    if (failCount > 0 && successCount == 0) {
      setState(() {
        _error = urls.length > 1 ? 'Failed to resolve links. Error: $firstError' : firstError;
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
      title: const Text('Add Links'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Paste Telegram message links to download their attached files. Separate multiple links with newlines or spaces.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_isLoading,
            maxLines: 4,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'https://t.me/...\nhttps://t.me/...',
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
                        final clipboardText = data?.text?.trim() ?? '';
                        if (clipboardText.isNotEmpty) {
                          final newText = _controller.text.isEmpty
                              ? clipboardText
                              : '${_controller.text}\n$clipboardText';
                          _controller.text = newText;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: newText.length),
                          );
                        }
                      },
                    )
                  : null,
            ),
            autofocus: true,
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
