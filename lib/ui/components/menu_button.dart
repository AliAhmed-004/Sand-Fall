import 'package:flutter/material.dart';
import 'package:sandfall/theme/theme.dart';

enum MenuButtonVariant {
  primary,
  secondary,
}

class MenuButton extends StatelessWidget {
  final String label;
  final String? sublabel;
  final VoidCallback onPressed;
  final MenuButtonVariant variant;

  const MenuButton({
    super.key,
    required this.label,
    this.sublabel,
    required this.onPressed,
    this.variant = MenuButtonVariant.primary,
  });

  const MenuButton.secondary({
    super.key,
    required this.label,
    this.sublabel,
    required this.onPressed,
  }) : variant = MenuButtonVariant.secondary;

  @override
  Widget build(BuildContext context) {
    final isSecondary = variant == MenuButtonVariant.secondary;

    return Container(
      width: double.infinity,
      height: isSecondary ? 52 : 64,
      decoration: BoxDecoration(
        color: isSecondary
            ? SandColors.deepSand.withAlpha(70)
            : SandColors.darkBg.withAlpha(150),
        borderRadius: BorderRadius.circular(isSecondary ? 8 : 2),
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: isSecondary
              ? SandColors.lightSand.withAlpha(220)
              : SandColors.primaryGold.withAlpha(180),
          side: BorderSide(
            color: isSecondary
                ? SandColors.primaryGold.withAlpha(120)
                : SandColors.deepSand.withAlpha(80),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isSecondary ? 8 : 2),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.5,
                fontFamily: 'monospace',
              ),
            ),
            if (sublabel != null)
              Text(
                sublabel!,
                style: TextStyle(
                  fontSize: 12,
                  color: SandColors.lightSand.withAlpha(100),
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
