import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/otp/hotp.dart';
import '../../core/otp/otp_types.dart';
import '../../core/otp/totp.dart';
import '../../data/account.dart';
import '../shared/motion.dart';
import '../shared/pressable.dart';
import '../shared/providers.dart';
import 'account_display.dart';
import 'accounts_strings.dart';
import 'countdown_ring.dart';
import 'edit_account_sheet.dart';

/// One account: its live code, a countdown (TOTP) or next-code button (HOTP),
/// tap-to-copy, and an options menu. Long-press drags to reorder (provided by
/// the list).
class AccountTile extends ConsumerStatefulWidget {
  const AccountTile({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends ConsumerState<AccountTile> {
  // HOTP: the code for the counter this tile last advanced to. Kept only in
  // memory; it is never re-derived from the stored counter, so a code is shown
  // only after the counter that produces it has been saved.
  String? _hotpCode;
  bool _advancing = false;

  // TOTP: the current code, recomputed only when the time step changes.
  int? _totpStep;
  String? _totpCode;

  // Inline "Copied" confirmation, shown briefly where the finger is.
  bool _copied = false;
  Timer? _copiedTimer;

  static const Duration _copiedFor = Duration(milliseconds: 1500);

  Account get _account => widget.account;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  String _totpCodeAt(DateTime now) {
    final step = Totp.timeStep(now, period: _account.period);
    if (step == _totpStep) {
      if (_totpCode case final cached?) return cached;
    }
    final code = Hotp.generate(
      _account.secret,
      counter: step,
      algorithm: _account.algorithm,
      digits: _account.digits,
    );
    _totpStep = step;
    _totpCode = code;
    return code;
  }

  @override
  void didUpdateWidget(AccountTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != _account.id) {
      _hotpCode = null;
      _totpStep = null;
      _totpCode = null;
    }
  }

  Future<void> _copy(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(secureClipboardProvider).copyCode(code);
    } on Exception {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(AccountsStrings.copyFailed)),
        );
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(_copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(AccountsStrings.copied)));
  }

  Future<void> _nextHotpCode() async {
    if (_advancing) return;
    setState(() => _advancing = true);
    try {
      final counter = await ref
          .read(accountRepositoryProvider)
          .incrementCounter(_account.id);
      if (!mounted) return;
      setState(() {
        _hotpCode = Hotp.generate(
          _account.secret,
          counter: counter,
          algorithm: _account.algorithm,
          digits: _account.digits,
        );
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AccountsStrings.saveFailed)));
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = accountTitle(_account);
    final subtitle =
        _account.issuer.isNotEmpty && _account.accountName.isNotEmpty
        ? _account.accountName
        : null;
    // Built once here rather than inside the TOTP Consumer: an identical
    // widget instance lets Flutter skip rebuilding the menu on every tick.
    final trailing = _menu();

    return switch (_account.type) {
      OtpType.totp => _totpTile(title, subtitle, trailing),
      OtpType.hotp => _hotpTile(title, subtitle, trailing),
    };
  }

  // Only the Consumer listens to the tick, so the rest of the tile is not
  // rebuilt every second.
  Widget _totpTile(String title, String? subtitle, Widget trailing) => Consumer(
    builder: (context, ref, _) {
      final now = ref.watch(tickProvider).value;
      final code = now == null ? null : _totpCodeAt(now);
      return _TileLayout(
        title: title,
        subtitle: subtitle,
        copied: _copied,
        code: code == null ? const SizedBox(height: 32) : _CodeText(code),
        leading: now == null
            ? const SizedBox.square(dimension: 40)
            : CountdownRing(
                remaining: Totp.remaining(now, period: _account.period),
                period: _account.period,
                step: Totp.timeStep(now, period: _account.period),
              ),
        onTap: code == null ? null : () => _copy(code),
        trailing: trailing,
      );
    },
  );

  Widget _hotpTile(String title, String? subtitle, Widget trailing) {
    final code = _hotpCode;
    return _TileLayout(
      title: title,
      subtitle: subtitle,
      copied: _copied,
      code: code == null
          ? Text(
              AccountsStrings.hotpHidden,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : _CodeText(code),
      leading: IconButton(
        tooltip: AccountsStrings.nextCode,
        onPressed: _advancing ? null : _nextHotpCode,
        icon: const Icon(Icons.refresh),
      ),
      onTap: code == null ? null : () => _copy(code),
      trailing: trailing,
    );
  }

  Widget _menu() => PopupMenuButton<_MenuAction>(
    tooltip: AccountsStrings.accountMenu,
    onSelected: (action) => switch (action) {
      _MenuAction.edit => showEditAccountSheet(context, _account),
      _MenuAction.move =>
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(AccountsStrings.reorderHint)),
          ),
      _MenuAction.delete => confirmDeleteAccount(context, ref, _account),
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: _MenuAction.edit, child: Text(AccountsStrings.edit)),
      PopupMenuItem(value: _MenuAction.move, child: Text(AccountsStrings.move)),
      PopupMenuItem(
        value: _MenuAction.delete,
        child: Text(AccountsStrings.delete),
      ),
    ],
  );
}

enum _MenuAction { edit, move, delete }

/// A visible code, grouped for reading and spelled out for screen readers.
/// When the code changes it crossfades instead of swapping abruptly.
class _CodeText extends StatelessWidget {
  const _CodeText(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: Motion.swap,
      switchInCurve: Motion.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: Semantics(
        key: ValueKey(code),
        label: AccountsStrings.codeLabel(code),
        excludeSemantics: true,
        child: Text(
          formatCode(code),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 2,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.leading,
    required this.onTap,
    required this.trailing,
    required this.copied,
  });

  final String title;
  final String? subtitle;
  final Widget code;
  final Widget leading;
  final VoidCallback? onTap;
  final Widget trailing;
  final bool copied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    return Pressable(
      enabled: onTap != null,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        minVerticalPadding: 12,
        // Fixed width so TOTP rings and the HOTP button line up the text.
        leading: SizedBox(width: 48, child: Center(child: leading)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: copied ? 1 : 0,
                  duration: Motion.feedback,
                  curve: Motion.easeOut,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: scheme.primary),
                      const SizedBox(width: 2),
                      Text(
                        AccountsStrings.copiedShort,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (subtitle case final subtitle?)
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            code,
          ],
        ),
        trailing: trailing,
      ),
    );
  }
}
