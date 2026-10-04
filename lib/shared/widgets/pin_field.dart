import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Obscured numeric input used for wallet PIN codes.
///
/// Adds a show/hide toggle and restricts input to digits so the field can be
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
    this.minLength = 6,
    this.maxLength = 8,
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
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: widget.maxLength,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscured ? 'Show' : 'Hide',
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
