import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'views/home_screen.dart'; // Importa a tela que criamos

void main() async {
  // Garante que as permissões nativas (storage/auth) funcionem antes do app abrir
  WidgetsFlutterBinding.ensureInitialized();

  // Trava a orientação (ex: apenas Portrait Up)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    // DeviceOrientation.portraitDown, // Opcional: permite de ponta cabeça
  ]);

  runApp(const CalibreDriveApp());
}

class CalibreDriveApp extends StatelessWidget {
  const CalibreDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calibre Drive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2A5CAA), // O azul do nosso ícone
          brightness: Brightness.light,
        ),
      ),
      // Define a HomeScreen como a tela inicial
      home: const HomeScreen(),
    );
  }
}
