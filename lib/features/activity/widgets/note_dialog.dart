import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/tx_notes_controller.dart';

/// Asks for a private note on a transaction.
///
/// Returns the text to save (blank removes the note), or `null` when the user
/// backed out and nothing should change.
Future<String?> showTxNoteDialog(
  BuildContext context, {
  String? initial,
}) {
  final TextEditingController controller =
      TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.sticky_note_2_outlined),
      title: Text(initial == null ? 'Add a note' : 'Edit note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: TxNotesController.maxLength,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'e.g. rent, invoice 1042',
          helperText: 'Only on this device. Included in the CSV export.',
          helperMaxLines: 2,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        if (initial != null)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Remove'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Edits the note on [hash] for [networkId] through [TxNotesController].
Future<void> editTxNote(
  BuildContext context, {
  required String networkId,
  required String hash,
}) async {
  final TxNotesController notes = context.read<TxNotesController>();
  final String? text = await showTxNoteDialog(
    context,
    initial: notes.noteFor(networkId, hash),
  );
  if (text != null) {
    await notes.setNote(networkId, hash, text);
  }
}
