import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utilis/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // Pour décoder le JSON

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<Map<String, dynamic>> _depots = [];
  int? _magasinId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final int? magId = await AuthService.getMagasinId();
    if (magId == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final List<Map<String, dynamic>> depots = await DatabaseHelper().getDepots(magId);
    
    if (!mounted) return;
    
    setState(() {
      _magasinId = magId;
      _depots = depots;
      _isLoading = false;
    });
  }

  void _changerDepot(Map<String, dynamic> user) async {
    int? selectedDepotId = user['depot_id'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Assigner à un dépôt"),
          content: DropdownButtonFormField<int>(
            initialValue: selectedDepotId, // Correction : initialValue au lieu de value
            items: _depots.map((d) => DropdownMenuItem(
              value: d['idDepot'] as int,
              child: Text(d['nomDepot']),
            )).toList(),
            onChanged: (val) {
              setDialogState(() => selectedDepotId = val);
            },
            decoration: const InputDecoration(labelText: "Sélectionner le dépôt"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
            ElevatedButton(
              onPressed: () async {
                if (selectedDepotId != null) {
                  await DatabaseHelper().changerDepotUtilisateur(user['idUser'], selectedDepotId!);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Dépôt mis à jour pour ${user['nomUser']}"))
                  );
                }
              },
              child: const Text("Confirmer"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestion des Utilisateurs"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper().getUtilisateurs(_magasinId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final users = snapshot.data ?? [];
                if (users.isEmpty) return const Center(child: Text("Aucun utilisateur trouvé"));

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    bool isActive = user['UserState'] == 1;
                    String nomDepot = user['nomDepot'] ?? "Aucun dépôt";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                          child: Icon(
                            user['niveauUser'] == 'boss' ? Icons.admin_panel_settings : Icons.person,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                        ),
                        title: Text("${user['nomUser']} (${user['niveauUser']})", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Dépôt: $nomDepot"),
                            Text(isActive ? "État : Actif" : "État : En attente", 
                                 style: TextStyle(color: isActive ? Colors.green : Colors.orange, fontSize: 12)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isActive)
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () async {
                                  await DatabaseHelper().validerUtilisateur(user['idUser']);
                                  _loadData();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Utilisateur activé !"))
                                  );
                                },
                              ),
                            if (user['niveauUser'] != 'boss')
                              IconButton(
                                icon: const Icon(Icons.warehouse, color: Colors.brown),
                                tooltip: "Changer de dépôt",
                                onPressed: () => _changerDepot(user),
                              ),
                          ],
                        ),
                        onLongPress: user['nomUser'] != 'admin' ? () async {
                          bool? confirm = await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Supprimer ?"),
                              content: Text("Voulez-vous supprimer l'utilisateur ${user['nomUser']} ?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await DatabaseHelper().supprimerUtilisateur(user['idUser']);
                            _loadData();
                          }
                        } : null,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
