import 'package:flutter/material.dart';
import 'package:my_business/database/database_helper.dart';
import 'package:my_business/utilis/auth_service.dart';
import 'package:my_business/utilis/sync_service.dart';
import 'StockPage.dart';
import 'liste_articles.dart';
import 'DashbordPage.dart';
import 'historique_ventes.dart';
import 'UserManagementPage.dart';
import 'login_page.dart';

class RapportPage extends StatefulWidget {
  const RapportPage({super.key});

  @override
  State<RapportPage> createState() => _RapportPageState();
}

class _RapportPageState extends State<RapportPage> {
  bool _isLoading = true;
  int? _magasinId;
  int? _selectedDepotId; 
  List<Map<String, dynamic>> _depots = [];
  String _role = "vendeur";
  
  // Variables pour la synchronisation
  bool _isSyncing = false;
  int _unsyncedCount = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkUnsynced();
  }

  void _loadUserData() async {
    final role = await AuthService.getRole();
    final depId = await AuthService.getDepotId();
    final magId = await AuthService.getMagasinId();

    if (magId == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
      return;
    }

    List<Map<String, dynamic>> depotsCharge = await DatabaseHelper().getDepots(magId);

    if (!mounted) return;

    setState(() {
      _role = role;
      _magasinId = magId;
      _depots = depotsCharge;
      _selectedDepotId = (role == 'boss') ? null : depId;
      _isLoading = false;
    });
  }

  Future<void> _checkUnsynced() async {
    int count = await DatabaseHelper().getUnsyncedCount();
    if (mounted) {
      setState(() => _unsyncedCount = count);
    }
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await SyncService().synchronizeData();
      await _checkUnsynced();
      
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _refreshKey++; 
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Rapport synchronisé !"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🚨 Échec sync : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _ouvrirNouveauMagasin() {
    final nomController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nouveau Magasin"),
        content: TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom de l'entreprise")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (nomController.text.isNotEmpty) {
                await DatabaseHelper().addMagasin(nomController.text);
                if (!mounted) return;
                Navigator.pop(context);
                _loadUserData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Magasin créé")));
              }
            },
            child: const Text("Créer"),
          ),
        ],
      ),
    );
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
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: _isSyncing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
                onPressed: _isSyncing ? null : _handleSync,
              ),
              if (_unsyncedCount > 0 && !_isSyncing)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$_unsyncedCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue.shade800),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shopping_basket, color: Colors.white, size: 40),
                  SizedBox(height: 10),
                  Text("Ma Gestion", style: TextStyle(color: Colors.white, fontSize: 24)),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.inventory, color: Colors.blue), title: const Text("Stock"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const StockPage())); }),
            ListTile(leading: const Icon(Icons.shopping_cart, color: Colors.green), title: const Text("Vendre"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const ListeArticles())); }),
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes())); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.dashboard), title: const Text("Tableau de Bord"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardPage())); }),
            if (_role == 'boss') ...[
               ListTile(leading: const Icon(Icons.add_business, color: Colors.brown), title: const Text("Nouveau Magasin"), onTap: () { Navigator.pop(context); _ouvrirNouveauMagasin(); }),
               ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.red), title: const Text("Vendeurs"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage())); }),
            ],
            ListTile(leading: const Icon(Icons.analytics, color: Colors.blue), title: const Text("Rapports"), onTap: () => Navigator.pop(context)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.grey), 
              title: const Text("Déconnexion"), 
              onTap: () async {
                bool confirm = await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Déconnexion"),
                    content: const Text("Voulez-vous vraiment vous déconnecter ?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
                    ],
                  ),
                ) ?? false;
                if (confirm) {
                  await AuthService.logout();
                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                }
              }
            ),
          ],
        ),
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
            child: RefreshIndicator(
              onRefresh: _handleSync,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey("rapport_$_selectedDepotId$_refreshKey"),
                future: DatabaseHelper().getRapportGlobal(
                  depotId: _selectedDepotId, 
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
                          subtitle: Text("Dépôt: ${item['nomDepot'] ?? 'N/A'}\nDate: $displayDate"),
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
          ),
        ],
      ),
    );
  }
}
