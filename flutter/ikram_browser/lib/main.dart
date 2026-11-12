import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'profiles_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IkramApp());
}

class IkramApp extends StatelessWidget {
  const IkramApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'إكرام',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
          scaffoldBackgroundColor: const Color(0xFFFFF0F5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.pinkAccent,
            foregroundColor: Colors.white,
          ),
        ),
        home: const ProfilesScreen(),
      );
}
