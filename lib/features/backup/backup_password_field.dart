import 'package:flutter/material.dart';

import 'backup_strings.dart';

/// A backup password field. Keyboard suggestions and learning are off in one
/// place, so the password never ends up in the keyboard's dictionary.
class BackupPasswordField extends StatelessWidget {
  const BackupPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.obscured,
    required this.onToggleObscured,
    this.helperText,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool obscured;
  final VoidCallback onToggleObscured;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscured,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        errorText: errorText,
        suffixIcon: IconButton(
          tooltip: obscured
              ? BackupStrings.showPassword
              : BackupStrings.hidePassword,
          icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggleObscured,
        ),
      ),
    );
  }
}
