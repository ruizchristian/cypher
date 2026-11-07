import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lock_service.dart';
import '../features/lock/pin_setup_screen.dart';
import '../features/lock/privacy_cover.dart';
import '../features/lock/unlock_screen.dart';
import '../features/shared/providers.dart';

/// Sits above the app's navigator (via `MaterialApp.builder`).
///
/// While setup is needed or the app is locked, only the lock screens exist:
/// the app's navigator is not in the tree at all, so no account screen, and
/// no half-finished add-account screen holding a secret, survives locking.
/// Unlocking always starts from the home screen.
///
/// It also reports background/foreground to [LockService] for auto-lock,
/// and covers the app whenever it is not in the foreground.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  /// The app's navigator, shown only while unlocked.
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> {
  late final AppLifecycleListener _lifecycle;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    final service = ref.read(lockServiceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        service.appResumed();
        setState(() => _covered = false);
      case AppLifecycleState.inactive:
        // Also fires for system dialogs (e.g. the biometric prompt), so it
        // only covers the screen; it does not start the auto-lock timer.
        setState(() => _covered = true);
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        service.appBackgrounded();
        setState(() => _covered = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(lockStateProvider).value ??
        ref.read(lockServiceProvider).state;
    final Widget body = switch (state) {
      LockUnlocked() => widget.child,
      LockNeedsSetup() => const _LockNavigator(
        key: ValueKey('setup'),
        screen: PinSetupScreen(),
      ),
      LockLocked() => const _LockNavigator(
        key: ValueKey('locked'),
        screen: UnlockScreen(),
      ),
      LockLoading() => const ColoredBox(color: Colors.transparent),
    };
    return Stack(
      fit: StackFit.expand,
      children: [body, if (_covered) const PrivacyCover()],
    );
  }
}

/// A minimal navigator for the lock screens, giving them an Overlay for
/// dialogs and tooltips without exposing the app's own routes.
class _LockNavigator extends StatelessWidget {
  const _LockNavigator({super.key, required this.screen});

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    // MaterialApp hands its HeroController to navigators below it, and a
    // HeroController may serve only one navigator. Without this, swapping
    // between the lock navigator and the app navigator crashes.
    return HeroControllerScope.none(
      child: Navigator(
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(builder: (_) => screen, settings: settings),
      ),
    );
  }
}
