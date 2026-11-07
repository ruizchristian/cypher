import 'package:flutter/material.dart';

import 'routes.dart';
import 'theme.dart';

class CypherApp extends StatelessWidget {
  const CypherApp({super.key});

  static const String title = 'CypherAuth';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.accounts,
      onGenerateRoute: onGenerateRoute,
    );
  }
}
