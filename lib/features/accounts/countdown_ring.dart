import 'package:flutter/material.dart';

import 'accounts_strings.dart';

/// Shows how much of the current TOTP period is left.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.period,
  });

  final Duration remaining;
  final int period;

  /// At or below this many seconds the ring switches to the warning colour.
  static const int warnAtSeconds = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final warn = seconds <= warnAtSeconds;
    return Semantics(
      label: AccountsStrings.secondsLeft(seconds),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: remaining.inMilliseconds / (period * 1000),
                strokeWidth: 3,
                color: warn ? scheme.error : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            Text(
              '$seconds',
              style: theme.textTheme.labelMedium?.copyWith(
                color: warn ? scheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
