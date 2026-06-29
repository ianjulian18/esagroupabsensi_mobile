import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESA Group Absensi',
      debugShowCheckedModeBanner:
          false, // Menghilangkan tulisan "Debug" di pojok kanan atas
      theme: ThemeData(
        brightness: Brightness
            .dark, // Menyesuaikan tema dasar agar serasi dengan dark mode
        primarySwatch: Colors.amber,
      ),
      home: const LoginScreen(), // Halaman pertama yang akan muncul
    );
  }
}
