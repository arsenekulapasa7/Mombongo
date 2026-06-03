import 'package:flutter/material.dart';
import 'liste_articles.dart';
import 'StockPage.dart';
import 'register_page.dart';
import '../database/database_helper.dart';
import '../utilis/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  @override
  void dispose() {
    _nomController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _login() async {
    String nom = _nomController.text.trim();
    String mdp = _passController.text.trim();

    if (nom.isEmpty || mdp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez remplir tous les champs")),
      );
      return;
    }

    try {
      final user = await DatabaseHelper().login(nom, mdp);

      if (user != null) {
        if (user['UserState'] == 1) {
          // Enregistrer les IDs dans la session
          // Correction : magasin_id et setMagasinId conformément à la v18 de la DB
          int magasinId = user['magasin_id'];
          int? depotId = user['depot_id'];
          String role = user['niveauUser'] ?? 'vendeur';
          
          await AuthService.setMagasinId(magasinId);
          if (depotId != null) await AuthService.setDepotId(depotId);
          await AuthService.setRole(role);

          if (!mounted) return;

          if (role == 'boss') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const StockPage()),
            );
          } else {
            if (depotId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Votre compte est actif, mais aucun dépôt ne vous a été assigné.")),
              );
              return;
            }
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ListeArticles()),
            );
          }
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Votre compte est en attente de validation par le Boss."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Nom d'utilisateur ou mot de passe incorrect"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur de connexion : $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "Connexion",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _nomController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Nom d'utilisateur",
                  labelStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.person, color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Mot de passe",
                  labelStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.key, color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade900,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _login,
                child: const Text("SE CONNECTER", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterPage()),
                  );
                },
                child: const Text(
                  "CRÉER UN COMPTE",
                  style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
