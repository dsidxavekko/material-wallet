import 'package:flutter/material.dart';

import 'pin_field.dart';

/// Modal that asks for the current PIN and returns it, or `null` on cancel.
///
/// Owns and disposes its [TextEditingController], unlike the ad-hoc dialogs it
/// replaces, so the entered PIN is not left referenced after the dialog closes.
class PinConfirmDialog extends StatefulWidget {
  const PinConfirmDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.icon = Icons.lock_outline_rounded,
  });

  final String title;
  final String confirmLabel;
  final IconData icon;

  /// Shows the dialog and resolves with the entered PIN, or `null`.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    IconData icon = Icons.lock_outline_rounded,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PinConfirmDialog(
        title: title,
        confirmLabel: confirmLabel,
        icon: icon,
      ),
    );
  }

  @override
  State<PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<PinConfirmDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(widget.icon),
      title: Text(widget.title),
      content: PinField(
        controller: _controller,
        label: 'PIN',
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
