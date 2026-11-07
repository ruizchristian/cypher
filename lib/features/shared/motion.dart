import 'package:flutter/widgets.dart';

/// Motion vocabulary for the whole app, so every animation shares one feel:
/// crisp and fast, as suits a security tool.
abstract final class Motion {
  /// Strong ease-out: starts fast, so the response feels immediate.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Press feedback (scale down while held).
  static const Duration press = Duration(milliseconds: 120);

  /// Content swaps such as a code changing.
  static const Duration swap = Duration(milliseconds: 160);

  /// Short confirmations such as "Copied".
  static const Duration feedback = Duration(milliseconds: 200);

  /// How far pressable elements shrink while held.
  static const double pressedScale = 0.97;

  /// Honours the system "remove animations" setting. Reduced motion means
  /// gentler, not none: callers keep fades and drop movement.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
