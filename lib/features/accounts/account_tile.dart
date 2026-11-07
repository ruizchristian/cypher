import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/otp/hotp.dart';
import '../../core/otp/otp_types.dart';
import '../../core/otp/totp.dart';
import '../../data/account.dart';
import '../shared/providers.dart';
import 'account_display.dart';
import 'accounts_strings.dart';
import 'countdown_ring.dart';
import 'edit_account_sheet.dart';

/// One account: its live code, a countdown (TOTP) or next-code button (HOTP),
/// tap-to-copy, and an options menu.
class AccountTile extends ConsumerStatefulWidget {
  const AccountTile({super.key, required this.account, this.dragIndex});

  final Account account;

  /// List index for the drag handle; `null` hides the handle (e.g. while
  /// searching).
  final int? dragIndex;

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

  Account get _account => widget.account;

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
    var message = AccountsStrings.copied;
    try {
      await ref.read(secureClipboardProvider).copyCode(code);
    } on Exception {
      message = AccountsStrings.copyFailed;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    // widget instance lets Flutter skip rebuilding the menu and drag handle
    // on every tick.
    final trailing = _trailing();

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
        code: code == null ? const SizedBox(height: 32) : _CodeText(code),
        leading: now == null
            ? const SizedBox.square(dimension: 40)
            : _countdown(now),
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
      code: code == null
          ? Text(
              AccountsStrings.hotpHidden,
              style: Theme.of(context).textTheme.bodyMedium,
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

  Widget _countdown(DateTime now) => CountdownRing(
    remaining: Totp.remaining(now, period: _account.period),
    period: _account.period,
  );

  Widget _trailing() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<_MenuAction>(
        tooltip: AccountsStrings.accountMenu,
        onSelected: (action) => switch (action) {
          _MenuAction.edit => showEditAccountSheet(context, _account),
          _MenuAction.delete => confirmDeleteAccount(context, ref, _account),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _MenuAction.edit,
            child: Text(AccountsStrings.edit),
          ),
          PopupMenuItem(
            value: _MenuAction.delete,
            child: Text(AccountsStrings.delete),
          ),
        ],
      ),
      if (widget.dragIndex case final index?)
        ReorderableDragStartListener(
          index: index,
          child: const Tooltip(
            message: AccountsStrings.reorderHandle,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ),
    ],
  );
}

enum _MenuAction { edit, delete }

/// A visible code, grouped for reading and spelled out for screen readers.
class _CodeText extends StatelessWidget {
  const _CodeText(this.code);

  final String code;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AccountsStrings.codeLabel(code),
    excludeSemantics: true,
    child: Text(
      formatCode(code),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 1.5,
      ),
    ),
  );
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.leading,
    required this.onTap,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget code;
  final Widget leading;
  final VoidCallback? onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      // Fixed width so TOTP rings and the HOTP button line up the text.
      leading: SizedBox(width: 48, child: Center(child: leading)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle case final subtitle?)
            Text(
              subtitle,
              style: textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          code,
        ],
      ),
      trailing: trailing,
    );
  }
}
