import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nomController = TextEditingController();
  final _passController = TextEditingController();
  final _entrepriseController = TextEditingController();
  String _niveau = 'vendeur'; 

  @override
  void dispose() {
    _nomController.dispose();
    _passController.dispose();
    _entrepriseController.dispose();
    super.dispose();
  }

  void _register() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    String nom = _nomController.text.trim();
    String pass = _passController.text.trim();
    String nomEntreprise = _entrepriseController.text.trim();

    if (nom.isEmpty || pass.isEmpty || nomEntreprise.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("Veuillez remplir tous les champs")),
      );
      return;
    }

    try {
      // Correction : Utilisation des paramètres nommés pour correspondre à DatabaseHelper.register
      await DatabaseHelper().register(
        nom: nom,
        mdp: pass,
        niveau: _niveau,
        nomMagasin: nomEntreprise,
      );

      if (!mounted) return;

      String message = (_niveau == 'boss')
          ? "Compte Boss et Entreprise '$nomEntreprise' créés ! Connectez-vous."
          : "Demande envoyée pour rejoindre '$nomEntreprise' ! Attendez la validation du Boss.";

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      String errorMsg = e.toString().replaceAll("Exception:", "").trim();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Créer un compte")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.business_center, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            TextField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: "Nom d'utilisateur", 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(
                labelText: "Mot de passe", 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _entrepriseController,
              decoration: const InputDecoration(
                labelText: "Nom de l'Entreprise / Magasin", 
                hintText: "Entrez le nom de votre structure",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: _niveau,
              items: const [
                DropdownMenuItem(value: 'vendeur', child: Text("Vendeur")),
                DropdownMenuItem(value: 'boss', child: Text("Boss")),
              ],
              onChanged: (v) => setState(() => _niveau = v!),
              decoration: const InputDecoration(
                labelText: "Niveau d'accès", 
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50)
              ),
              onPressed: _register,
              child: const Text("S'INSCRIRE"),
            ),
          ],
        ),
      ),
    );
  }
}
