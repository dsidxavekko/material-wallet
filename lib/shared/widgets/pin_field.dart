import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';

/// Shortest password accepted when a new one is set or changed.
///
/// Unlocking has no minimum: a wallet created with the old 6–8 digit PIN keeps
/// working, because the vault treats the secret as an opaque string.
const int kMinPasswordLength = 8;

/// Obscured text input used for the wallet password (formerly a numeric PIN).
///
/// Adds a show/hide toggle; any characters are allowed so the field can be
/// reused on the lock screen and in the create/import flows.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.enabled = true,
    this.errorText,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.minLength = kMinPasswordLength,
    this.maxLength = 64,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool enabled;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int minLength;
  final int maxLength;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: _obscured,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: widget.maxLength,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscured ? context.l10n.showLabel : context.l10n.hideLabel,
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
