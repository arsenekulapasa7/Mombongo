import 'package:flutter/material.dart';
import '../utilis/auth_service.dart';
import 'login_page.dart';

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _validerActivation() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    // On utilise la fonction de AuthService
    bool success = await AuthService.authorizeDevice(_codeController.text);
    
    if (success) {
      if (!mounted) return;
      // Après l'activation, on redirige vers la page de Login
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage())
      );
    } else {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Code d'activation incorrect !")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 80, color: Colors.blue.shade800),
            const SizedBox(height: 20),
            const Text("Activation de l'Application", 
                 style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Cet appareil n'est pas encore autorisé. Veuillez contacter votre fournisseur pour obtenir une clé d'activation.",
                 textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: "Clé d'activation",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: _validerActivation,
              child: const Text("ACTIVER L'APPAREIL"),
            )
          ],
        ),
      ),
    );
  }
}
