import 'package:flutter/material.dart';

import 'motion.dart';

/// Shrinks its child slightly while a finger is down, so the interface
/// visibly "hears" the press. It only observes pointers; the child keeps its
/// own tap handling, semantics and ink.
///
/// Under reduced motion the scale is skipped.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !Motion.reduced(context);
    return Listener(
      onPointerDown: active ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active && _down ? Motion.pressedScale : 1,
        duration: Motion.press,
        curve: Motion.easeOut,
        child: widget.child,
      ),
    );
  }
}
