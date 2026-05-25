import 'package:flutter/material.dart';
import 'package:sandfall/theme/theme.dart';

Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'CONTINUE',
  String cancelLabel = 'ABORT',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: SandColors.darkBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          style: const TextStyle(
            color: SandColors.primaryGold,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontFamily: 'monospace',
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: SandColors.lightSand,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: SandColors.primaryGold,
              foregroundColor: SandColors.darkBg,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  return result ?? false;
}