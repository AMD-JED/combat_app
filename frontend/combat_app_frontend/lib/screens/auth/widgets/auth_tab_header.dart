import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The login/register segmented switcher shown atop both auth screens,
/// matching the tab toggle in the Athletes Hub design reference
/// (AuthModal.tsx). Tapping the inactive side navigates to the other route.
class AuthTabHeader extends StatelessWidget {
  final bool isLogin;
  final String loginLabel;
  final String registerLabel;

  const AuthTabHeader({
    super.key,
    required this.isLogin,
    required this.loginLabel,
    required this.registerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: loginLabel,
              active: isLogin,
              accent: accent,
              onTap: () => context.go('/login'),
            ),
          ),
          Expanded(
            child: _Segment(
              label: registerLabel,
              active: !isLogin,
              accent: accent,
              onTap: () => context.go('/register'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: active ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: active ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
