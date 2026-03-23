import 'package:flutter/material.dart';
// Corregí la ruta para que apunte a 'pages' que es donde tienes el archivo
import 'pages/profile_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor de Perfiles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B63FF)),
        useMaterial3: true,
      ),
      // Ahora sí reconocerá el ProfileScreen
      home: const ProfileScreen(),
    );
  }
}