import 'package:flutter/material.dart';
import 'package:my_business/database/database_helper.dart';
import 'package:my_business/utilis/auth_service.dart';

class RapportPage extends StatefulWidget {
  const RapportPage({super.key});

  @override
  State<RapportPage> createState() => _RapportPageState();
}

class _RapportPageState extends State<RapportPage> {
  bool _isLoading = true;
  int? _magasinId;
  int? _selectedDepotId; // null = global pour le magasin
  List<Map<String, dynamic>> _depots = [];
  String _role = "vendeur";

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    final role = await AuthService.getRole();
    final depId = await AuthService.getDepotId();
    final magId = await AuthService.getMagasinId();

    List<Map<String, dynamic>> depotsCharge = [];

    if (magId != null && role == 'boss') {
      depotsCharge = await DatabaseHelper().getDepots(magId);
    }

    if (!mounted) return;

    setState(() {
      _role = role;
      _magasinId = magId;
      _depots = depotsCharge;
      _selectedDepotId = (role == 'boss') ? null : depId;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rapport d'Activités"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_role == 'boss')
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: DropdownButtonFormField<int?>(
                value: _selectedDepotId,
                decoration: const InputDecoration(
                  labelText: "Filtrer par Dépôt",
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Global (Mon Entreprise)")),
                  ..._depots.map((d) => DropdownMenuItem(
                        value: d['idDepot'],
                        child: Text(d['nomDepot'] as String),
                      )),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedDepotId = val;
                  });
                },
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper().getRapportGlobal(
                _selectedDepotId, 
                magasinId: _magasinId
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Erreur : ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Aucune activité enregistrée."));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final item = snapshot.data![index];
                    final type = item['type'] ?? 'INCONNU';

                    Color color = Colors.blue;
                    IconData icon = Icons.add_box;
                    
                    if (type == 'VENTE') {
                      color = Colors.red;
                      icon = Icons.shopping_cart;
                    } else if (type == 'REAPPRO') {
                      color = Colors.green;
                      icon = Icons.refresh;
                    } else if (type == 'ENTREE') {
                      color = Colors.blue;
                      icon = Icons.login;
                    }

                    final String dateStr = item['date']?.toString() ?? "";
                    final displayDate = dateStr.length >= 16 
                        ? dateStr.substring(0, 16).replaceAll('T', ' ') 
                        : dateStr;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.1),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(
                          "${item['nom_produit']} ($type)",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("Date: $displayDate"),
                        trailing: Text(
                          "${type == 'VENTE' ? '-' : '+'}${item['quantite']}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: color, 
                            fontSize: 18
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
