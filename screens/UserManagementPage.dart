import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utilis/auth_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<Map<String, dynamic>> _depots = [];
  int? _magasinId;
  bool _isLoading = true;
  int _refreshKey = 0;

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
      _depots = List.from(depots); 
      _isLoading = false;
      _refreshKey++;
    });
  }

  void _creerNouveauDepot() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nouveau Point de Vente"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Nom du dépôt / point de vente"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && _magasinId != null) {
                await DatabaseHelper().addDepot(controller.text, _magasinId!);
                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text("Créer"),
          ),
        ],
      ),
    );
  }

  void _changerDepot(Map<String, dynamic> user) async {
    int? selectedDepotId = user['depot_id'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Assigner à un dépôt"),
          content: DropdownButtonFormField<int>(
            value: _depots.any((d) => d['idDepot'] == selectedDepotId) ? selectedDepotId : null,
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
        title: const Text("Vendeurs & Dépôts"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business),
            onPressed: _creerNouveauDepot,
            tooltip: "Ajouter un dépôt",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _loadData(),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey(_refreshKey),
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
                      String nomDepot = user['nomDepot'] ?? "Non assigné";

                      return Dismissible(
                        key: ValueKey(user['idUser']),
                        direction: user['niveauUser'] != 'boss' ? DismissDirection.endToStart : DismissDirection.none,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Supprimer l'utilisateur"),
                              content: Text("Voulez-vous vraiment supprimer ${user['nomUser']} ?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async {
                          await DatabaseHelper().supprimerUtilisateur(user['idUser']);
                          _loadData();
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                              child: Icon(
                                user['niveauUser'] == 'boss' ? Icons.admin_panel_settings : Icons.person,
                                color: isActive ? Colors.green : Colors.grey,
                              ),
                            ),
                            title: Text("${user['nomUser']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Dépôt : $nomDepot"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isActive)
                                  IconButton(
                                    icon: const Icon(Icons.check_circle, color: Colors.green),
                                    onPressed: () async {
                                      await DatabaseHelper().validerUtilisateur(user['idUser']);
                                      _loadData();
                                    },
                                  ),
                                if (user['niveauUser'] != 'boss')
                                  IconButton(
                                    icon: const Icon(Icons.warehouse, color: Colors.brown),
                                    onPressed: () => _changerDepot(user),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
