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
  // Correction ici : Initialisation du contrôleur unique pour la boutique
  final _boutiqueController = TextEditingController();
  String _niveau = 'vendeur';

  @override
  void dispose() {
    _nomController.dispose();
    _passController.dispose();
    _boutiqueController.dispose();
    super.dispose();
  }

  void _register() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String nom = _nomController.text.trim();
    String pass = _passController.text.trim();
    String boutiqueSaisie = _boutiqueController.text.trim();

    // 1. Validation des champs vides
    if (nom.isEmpty || pass.isEmpty || boutiqueSaisie.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("Veuillez remplir tous les champs")),
      );
      return;
    }

    try {
      // APPEL À LA BASE DE DONNÉES
      // Le DatabaseHelper va vérifier si la boutique existe pour le vendeur
      // ou la créer si c'est un Boss.
      await DatabaseHelper().register(
        nom: nom,
        mdp: pass,
        niveau: _niveau,
        nomMagasin: boutiqueSaisie,
      );

      if (!mounted) return;

      String message = (_niveau == 'boss')
          ? "Compte Boss et boutique '$boutiqueSaisie' créés !"
          : "Demande envoyée ! Attendez la validation du Boss de '$boutiqueSaisie'.";

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
      navigator.pop();

    } catch (e) {
      if (!mounted) return;

      String errorMsg = e.toString();

      // LOGIQUE D'UNICITÉ ET DE VÉRIFICATION
      if (errorMsg.contains("UNIQUE constraint failed")) {
        if (errorMsg.contains("nomUser")) {
          errorMsg = "Ce nom d'utilisateur est déjà utilisé.";
        } else if (errorMsg.contains("nomMagasin")) {
          errorMsg = "Une boutique porte déjà ce nom.";
        } else {
          errorMsg = "Ce compte ou cette boutique existe déjà.";
        }
      } else if (errorMsg.contains("n'existe pas")) {
        // C'est ici que l'on bloque le vendeur si la boutique n'existe pas
        errorMsg = "Erreur : La boutique '$boutiqueSaisie' n'existe pas encore. Le Boss doit la créer d'abord.";
      } else {
        errorMsg = errorMsg.replaceAll("Exception:", "").trim();
      }

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
            const Icon(Icons.person_add, size: 80, color: Colors.blue),
            const SizedBox(height: 20),

            // CHAMP NOM
            TextField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: "Nom d'utilisateur",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 15),

            // CHAMP MOT DE PASSE
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

            // CHAMP BOUTIQUE (POUR TOUS)
            TextField(
              controller: _boutiqueController,
              decoration: InputDecoration(
                // Libellé dynamique selon le rôle choisi
                labelText: _niveau == 'boss' ? "Nom de votre  boutique" : "Boutique à rejoindre",
                hintText: _niveau == 'boss' ? "Ex: Ma Boutique" : "Saisissez le nom exact du dépôt",
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 15),

            // CHOIX DU NIVEAU
            DropdownButtonFormField<String>(
              value: _niveau,
              items: const [
                DropdownMenuItem(value: 'vendeur', child: Text("Vendeur ")),
                DropdownMenuItem(value: 'boss', child: Text("Boss ")),
              ],
              onChanged: (v) => setState(() => _niveau = v!),
              decoration: const InputDecoration(
                labelText: "Type de compte",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),

            // BOUTON VALIDER
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