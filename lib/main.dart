import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Tema Merah Arina Multikarya / SADATA
    const primaryColor = Color(0xFF2E3190);

    return MaterialApp(
      title: 'ESA Group Absensi',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light, // Paksa tema terang agar konsisten dengan desain
      
      // Pengaturan Tema Terang (Light Mode)
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB), // Warna background abu-abu terang
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
          primary: primaryColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      
      home: const LoginScreen(), // Halaman pertama yang akan muncul
    );
  }
}
