import 'package:flutter/material.dart';

import '../shared/motion.dart';
import 'accounts_strings.dart';

/// Shows how much of the current TOTP period is left.
///
/// The ring sweeps continuously: each tick animates linearly to where it will
/// be one second later (constant motion, so linear easing). A new period
/// remounts the animation, so the ring refills instantly instead of
/// sweeping backwards. Under reduced motion it steps once per second.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.period,
    required this.step,
  });

  final Duration remaining;
  final int period;

  /// The current time step; a change means a new period has started.
  final int step;

  /// At or below this many seconds the ring switches to the warning colour.
  static const int warnAtSeconds = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final warn = seconds <= warnAtSeconds;
    final periodMs = period * 1000;
    final now = remaining.inMilliseconds / periodMs;
    final inOneSecond = ((remaining.inMilliseconds - 1000) / periodMs).clamp(
      0.0,
      1.0,
    );
    final color = warn ? scheme.error : scheme.primary;
    final reduced = Motion.reduced(context);

    Widget ring(double value) => CircularProgressIndicator(
      value: value,
      strokeWidth: 3,
      strokeCap: StrokeCap.round,
      color: color,
      backgroundColor: scheme.surfaceContainerHighest,
    );

    return Semantics(
      label: AccountsStrings.secondsLeft(seconds),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The ring repaints every frame while it sweeps; a boundary keeps
            // that to the ring instead of the whole list.
            SizedBox.expand(
              child: RepaintBoundary(
                child: reduced
                    ? ring(now)
                    : TweenAnimationBuilder<double>(
                        key: ValueKey(step),
                        tween: Tween(begin: now, end: inOneSecond),
                        duration: const Duration(seconds: 1),
                        curve: Curves.linear,
                        builder: (_, value, _) => ring(value),
                      ),
              ),
            ),
            Text(
              '$seconds',
              style: theme.textTheme.labelMedium?.copyWith(
                color: warn ? scheme.error : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
