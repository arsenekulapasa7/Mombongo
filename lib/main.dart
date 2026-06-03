import 'package:flutter/material.dart';
import 'package:my_business/screens/activation_page.dart';
import 'package:my_business/screens/login_page.dart';
import 'package:my_business/utilis/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Vérifie si l'appareil est déjà autorisé (activé)
  final bool isAuthorized = await AuthService.isAppAuthorized();

  runApp(MonAppGestion(isAuthorized: isAuthorized));
}

class MonAppGestion extends StatelessWidget {
  final bool isAuthorized;

  const MonAppGestion({super.key, required this.isAuthorized});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haodjin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Si autorisé, on va au Login, sinon à la page d'Activation
      home: isAuthorized ? const LoginPage() : const ActivationPage(),
    );
  }
}
