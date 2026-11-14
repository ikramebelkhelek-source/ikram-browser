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
        title: 'إكرام سيف',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF176B68),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF176B68),
            onPrimary: Colors.white,
            secondary: const Color(0xFFE46F32),
            surface: const Color(0xFFFFFCF6),
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F2E9),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF173B3F),
            foregroundColor: Color(0xFFFFFCF6),
            centerTitle: false,
            elevation: 0,
          ),
          cardTheme: const CardThemeData(
            color: Color(0xFFFFFCF6),
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFFFCF6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD4DFD9)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD4DFD9)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFF176B68),
                width: 1.6,
              ),
            ),
          ),
        ),
        home: const ProfilesScreen(),
      );
}
