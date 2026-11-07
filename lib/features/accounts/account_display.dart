import '../../data/account.dart';
import 'accounts_strings.dart';

/// "287082" -> "287 082"; "12345678" -> "1234 5678"; "1234567" -> "1234 567".
String formatCode(String code) {
  final split = (code.length / 2).ceil();
  return '${code.substring(0, split)} ${code.substring(split)}';
}

/// The primary label for an account: the issuer, else the account name.
String accountTitle(Account account) => account.issuer.isNotEmpty
    ? account.issuer
    : account.accountName.isNotEmpty
    ? account.accountName
    : AccountsStrings.untitled;
