import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/home/dashboard_page.dart';

class AppWidget extends StatelessWidget {
  const AppWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle Financeiro',

      // 🌍 Locale padrão Brasil
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],

      // 🔤 Delegates obrigatórios
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // 🎨 Tema
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),

      home: const DashboardPage(),
    );
  }
}
