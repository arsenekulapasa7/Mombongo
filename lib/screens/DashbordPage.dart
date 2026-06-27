import 'package:flutter/material.dart';
import 'package:my_business/database/database_helper.dart';
import 'package:my_business/utilis/auth_service.dart';
import 'package:my_business/utilis/sync_service.dart';
import 'StockPage.dart';
import 'liste_articles.dart';
import 'historique_ventes.dart';
import 'RapportPage.dart';
import 'UserManagementPage.dart';
import 'login_page.dart';
import '../models/configuration.dart';
import 'package:http/http.dart' as http;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, double>> _statsFuture;
  int? _magasinId;
  int? _selectedFilterDepotId;
  List<Map<String, dynamic>> _allDepots = [];
  String _role = "vendeur";
  bool _isSyncing = false;
  int _unsyncedCount = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _statsFuture = Future.value({'stock': 0, 'recette_jour': 0, 'recette_mois': 0});
    _initData();
    _checkUnsynced();
  }

  void _initData() async {
    final int? magId = await AuthService.getMagasinId();
    final int? depId = await AuthService.getDepotId();
    final String role = await AuthService.getRole();

    if (magId == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
      return;
    }

    List<Map<String, dynamic>> depots = await DatabaseHelper().getDepots(magId);

    if (!mounted) return;

    setState(() {
      _magasinId = magId;
      _role = role;
      _allDepots = depots;
      _selectedFilterDepotId = (role == 'boss') ? null : depId;
      _refreshStats();
    });
  }

  Future<void> _checkUnsynced() async {
    int count = await DatabaseHelper().getUnsyncedCount();
    if (mounted) {
      setState(() { _unsyncedCount = count; });
    }
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = DatabaseHelper().getStatistiques(
        _selectedFilterDepotId,
        magasinId: _magasinId
      );
    });
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await SyncService().synchronizeData();
      await _checkUnsynced();
      _refreshStats();
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _refreshKey++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Statistiques synchronisées !"), backgroundColor: Colors.green),
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

  void _afficherConfiguration() {
    Config currentConfig = Config(
        configurationTableFile: "'magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'",
        fileName: 'MaGestion.db',
        body: 'Liaison avec le serveur distant',
        apiUrl: 'http://afrisofttech-002-site50.jtempurl.com/'
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configuration du Serveur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("URL de l'API :", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(currentConfig.apiUrl, style: const TextStyle(color: Colors.blue, fontSize: 13)),
            const SizedBox(height: 10),
            Text("Base locale : ${currentConfig.fileName}"),
            const SizedBox(height: 10),
            Text("Statut : ${currentConfig.body}"),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.sync_alt),
            label: const Text("Vérifier Liaison"),
            onPressed: () async {
              try {
                final response = await http.get(Uri.parse(currentConfig.apiUrl)).timeout(const Duration(seconds: 10));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Connecté au serveur API (${response.statusCode})"), backgroundColor: Colors.green)
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Erreur : Impossible de contacter l'API"), backgroundColor: Colors.red)
                  );
                }
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer")),
        ],
      ),
    );
  }

  void _ouvrirNouveauMagasin() {
    final nomController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nouveau Magasin"),
        content: TextField(
            controller: nomController,
            decoration: const InputDecoration(labelText: "Nom de l'entreprise")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (nomController.text.isNotEmpty) {
                await DatabaseHelper().register(
                    nom: nomController.text,
                    mdp: "1234",
                    niveau: 'boss',
                    nomMagasin: nomController.text
                );
                if (!mounted) return;
                Navigator.pop(context);
                _initData();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Magasin et Dépôt créés avec succès"))
                );
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
    if (_magasinId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tableau de Bord"),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshStats),
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

            ListTile(leading: const Icon(Icons.shopping_cart, color: Colors.green), title: const Text("Vendre"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const ListeArticles())); }),
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes())); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.dashboard, color: Colors.blue), title: const Text("Tableau de Bord"), onTap: () => Navigator.pop(context)),
            if (_role == 'boss') ...[
              ListTile(leading: const Icon(Icons.inventory, color: Colors.blue), title: const Text("Stock"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const StockPage())); }),
               ListTile(leading: const Icon(Icons.add_business, color: Colors.brown), title: const Text("Nouveau Magasin"), onTap: () { Navigator.pop(context); _ouvrirNouveauMagasin(); }),
               ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.red), title: const Text("Vendeurs"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage())); }),
            ],
            ListTile(leading: const Icon(Icons.analytics), title: const Text("Rapports"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const RapportPage())); }),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.blueGrey),
              title: const Text("Configuration API"),
              onTap: () {
                Navigator.pop(context);
                _afficherConfiguration();
              }
            ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: DropdownButtonFormField<int?>(
                value: _selectedFilterDepotId,
                decoration: const InputDecoration(
                  labelText: "Filtrer par Dépôt",
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Global (Mon Entreprise)")),
                  ..._allDepots.map((d) => DropdownMenuItem(
                    value: d['idDepot'],
                    child: Text(d['nomDepot']),
                  )),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedFilterDepotId = val;
                  });
                  _refreshStats();
                },
              ),
            ),
          Expanded(
            child: FutureBuilder<Map<String, double>>(
              key: ValueKey("stats_$_refreshKey"),
              future: _statsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Erreur : ${snapshot.error}"));
                }

                final data = snapshot.data ?? {};

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildStatCard("Valeur du Stock", "${data['stock']?.toStringAsFixed(2) ?? '0.00'} USD", Colors.blue),
                        const SizedBox(height: 16),
                        _buildStatCard("Recette du Jour", "${data['recette_jour']?.toStringAsFixed(2) ?? '0.00'} USD", Colors.green),
                        const SizedBox(height: 16),
                        _buildStatCard("Recette du Mois", "${data['recette_mois']?.toStringAsFixed(2) ?? '0.00'} USD", Colors.orange),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
