import 'package:flutter/material.dart';

import '../security/password_security.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.strength});

  final PasswordStrength strength;

  Color _color(BuildContext context) {
    return switch (strength.score) {
      0 => const Color(0xFFC62828),
      1 => const Color(0xFFE65100),
      2 => const Color(0xFFF9A825),
      3 => const Color(0xFF2E7D32),
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Semantics(
      label: '密码强度${strength.label}',
      child: Row(
        children: [
          Text('密码强度', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (strength.score + 1) / 5,
                minHeight: 6,
                color: color,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              strength.label,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
