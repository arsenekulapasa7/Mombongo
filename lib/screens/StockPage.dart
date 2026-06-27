import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:my_business/database/database_helper.dart';
import 'package:my_business/models/articles.dart';
import 'package:my_business/screens/RapportPage.dart';
import 'package:my_business/screens/DashbordPage.dart';
import 'package:my_business/utilis/auth_service.dart';
import 'package:my_business/screens/login_page.dart';
import 'package:my_business/screens/UserManagementPage.dart';
import 'package:my_business/screens/liste_articles.dart';
import 'package:my_business/screens/historique_ventes.dart';
import 'package:my_business/utilis/sync_service.dart';
import '../models/configuration.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String _searchQuery = "";
  int? _currentDepotId;
  int? _magasinId;
  String _nomDepot = "Mon Dépôt";
  List<Map<String, dynamic>> _allDepots = [];
  int? _selectedFilterDepotId; 
  String _role = "vendeur"; 
  int _refreshKey = 0;
  int _unsyncedCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkUnsynced();
  }

  void _loadUserData() async {
    final depId = await AuthService.getDepotId();
    final magId = await AuthService.getMagasinId();
    final roleRaw = await AuthService.getRole();
    final role = roleRaw.toLowerCase().trim();

    if (magId == null) {
       if (!mounted) return;
       Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
       return;
    }

    final List<Map<String, dynamic>> depots = await DatabaseHelper().getDepots(magId);

    String nomDep = "Mon Dépôt";
    if (depId != null) {
      final found = depots.any((d) => d['idDepot'] == depId);
      if (found) {
        nomDep = depots.firstWhere((d) => d['idDepot'] == depId)['nomDepot'];
      }
    }

    if (!mounted) return;

    setState(() {
      _currentDepotId = depId;
      _magasinId = magId;
      _nomDepot = nomDep;
      _role = role;
      _allDepots = depots;
      _selectedFilterDepotId = (role == 'boss') ? null : depId;
    });
  }

  Future<void> _checkUnsynced() async {
    int count = await DatabaseHelper().getUnsyncedCount();
    if (mounted) {
      setState(() { _unsyncedCount = count; });
    }
  }

  Future<void> _handleSync() async {
    await startSynchronization();
  }

  Future<void> startSynchronization() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final url = Uri.parse('http://afrisofttech-002-site50.jtempurl.com/api/SynchronizeSync/Synchronization');

    try {
      final db = await DatabaseHelper().database;
      final List<String> tables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
      Map<String, List<Map<String, dynamic>>> payload = {};

      for (String table in tables) {
        List<Map<String, dynamic>> unsynced = await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
        if (unsynced.isNotEmpty) {
          payload[table] = unsynced;
        }
      }

      if (payload.isEmpty) {
        await SyncService().synchronizeData(); 
        await _checkUnsynced();
        if (mounted) {
          setState(() { _isSyncing = false; _refreshKey++; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Vos données sont déjà à jour.")));
        }
        return;
      }

      final Map<String, dynamic> requestBody = {
        "serverConnexionString": "Data Source=SQL5083.site4now.net;Initial Catalog=db_a54efd_synchronizedb;User Id=db_a54efd_synchronizedb_admin;Password=12345678GL;Encrypt=True;TrustServerCertificate=True",
        "localDb": "MaGestion.db",
        "fileName": "MaGestion.db",
        "body": payload 
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        for (String table in payload.keys) {
          await db.update(table, {'is_synced': 1}, where: 'is_synced = ?', whereArgs: [0]);
        }
        if (_magasinId != null) await SyncService().synchronizeData(); 
        await _checkUnsynced();
        if (mounted) {
          setState(() { _isSyncing = false; _refreshKey++; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ SYNCHRONISATION RÉUSSIE !"), backgroundColor: Colors.green));
        }
      } else {
        throw Exception("Erreur serveur (${response.statusCode})");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🚨 ÉCHEC SYNC : $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _afficherConfiguration() {
    Config currentConfig = Config(
        configurationTableFile: "'magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'",
        fileName: 'MaGestion.db',
        body: 'Système relié à l\'API',
        apiUrl: 'http://afrisofttech-002-site50.jtempurl.com'
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configuration du Serveur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text("Base locale : ${currentConfig.fileName}"),
            const SizedBox(height: 10),
            const Text("URL API :", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(currentConfig.apiUrl, style: const TextStyle(fontSize: 12, color: Colors.blue)),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Serveur contacté (${response.statusCode})"), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible de contacter le serveur"), backgroundColor: Colors.red));
                }
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer")),
        ],
      ),
    );
  }

  void _ouvrirFormulaireAjout(BuildContext context) {
    if (_role != 'boss') return;

    final nomController = TextEditingController();
    final qteController = TextEditingController();
    final prixController = TextEditingController();

    int? targetDepotId = _selectedFilterDepotId ?? (_allDepots.isNotEmpty ? _allDepots[0]['idDepot'] : _currentDepotId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Nouvel Article", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              DropdownButtonFormField<int>(
                value: targetDepotId,
                decoration: const InputDecoration(labelText: "Dépôt"),
                items: _allDepots.map((d) => DropdownMenuItem<int>(value: d['idDepot'] as int, child: Text(d['nomDepot'] as String))).toList(),
                onChanged: (val) => setModalState(() => targetDepotId = val),
              ),
              TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom")),
              TextField(controller: qteController, decoration: const InputDecoration(labelText: "Quantité"), keyboardType: TextInputType.number),
              TextField(controller: prixController, decoration: const InputDecoration(labelText: "Prix (USD)"), keyboardType: TextInputType.number),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45)),
                onPressed: () async {
                  if (targetDepotId == null || nomController.text.trim().isEmpty) return;
                  await DatabaseHelper().insertProduit({
                    'nom': nomController.text,
                    'quantite': int.tryParse(qteController.text) ?? 0,
                    'prix_unitaire': double.tryParse(prixController.text) ?? 0.0,
                  }, targetDepotId!);
                  _checkUnsynced();
                  if (!mounted) return;
                  Navigator.pop(context);
                  setState(() { _refreshKey++; });
                },
                child: const Text("Enregistrer"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _ouvrirReappro(BuildContext context, Article art) {
    if (_role != 'boss') return;

    final reapproController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Réapprovisionner ${art.nom}"),
        content: TextField(controller: reapproController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantité")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              int qte = int.tryParse(reapproController.text) ?? 0;
              if (qte > 0 && art.id != null) {
                int? depotId = art.depotId ?? _selectedFilterDepotId ?? _currentDepotId;
                if (depotId != null) {
                  await DatabaseHelper().reaprovisionner(art.id!, qte, depotId);
                  _checkUnsynced();
                  if (!mounted) return;
                  Navigator.pop(context);
                  setState(() { _refreshKey++; });
                }
              }
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestion Stock"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload),
                onPressed: _isSyncing ? null : _handleSync,
              ),
              if (_unsyncedCount > 0 && !_isSyncing)
                Positioned(right: 8, top: 8, child: CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Text('$_unsyncedCount', style: const TextStyle(color: Colors.white, fontSize: 8)))),
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
            ListTile(leading: const Icon(Icons.inventory, color: Colors.blue), title: const Text("Stock"), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.shopping_cart, color: Colors.green), title: const Text("Vendre"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const ListeArticles())); }),
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes())); }),
            const Divider(),
            if (_role == 'boss') ...[
               ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.red), title: const Text("Vendeurs"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage())); }),
               const Divider(),
            ],
            ListTile(leading: const Icon(Icons.dashboard, color: Colors.blue), title: const Text("Dashboard"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardPage())); }),
            ListTile(leading: const Icon(Icons.analytics, color: Colors.purple), title: const Text("Rapports"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const RapportPage())); }),
            ListTile(leading: const Icon(Icons.settings, color: Colors.blueGrey), title: const Text("Configuration"), onTap: () { Navigator.pop(context); _afficherConfiguration(); }),
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
                value: _selectedFilterDepotId,
                items: [
                  const DropdownMenuItem(value: null, child: Text("Global")),
                  ..._allDepots.map((d) => DropdownMenuItem(value: d['idDepot'] as int, child: Text(d['nomDepot'] as String))),
                ],
                onChanged: (val) { setState(() { _selectedFilterDepotId = val; _refreshKey++; }); },
                decoration: const InputDecoration(labelText: "Filtrer par Dépôt", border: OutlineInputBorder()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(onChanged: (v) => setState(() => _searchQuery = v), decoration: const InputDecoration(labelText: "Rechercher", prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey("stock_$_refreshKey"),
              future: DatabaseHelper().getProduits(_selectedFilterDepotId, magasinId: _magasinId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun article."));
                
                final list = snapshot.data!.where((item) => item['nom'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final art = Article.fromMap(item);
                    return Dismissible(
                      key: ValueKey(art.id),
                      direction: _role == 'boss' ? DismissDirection.endToStart : DismissDirection.none,
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
                            title: const Text("Confirmer"),
                            content: const Text("Voulez-vous supprimer cet article ?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        await DatabaseHelper().deleteProduit(art.id!);
                        _checkUnsynced();
                      },
                      child: ListTile(
                        title: Text(art.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Prix: ${art.prix} USD | Stock: ${art.quantite}"),
                        trailing: _role == 'boss' ? IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => _ouvrirReappro(context, art)) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _role == 'boss' ? FloatingActionButton(
        onPressed: () => _ouvrirFormulaireAjout(context), 
        backgroundColor: Colors.blue.shade800,
        child: const Icon(Icons.add, color: Colors.white)
      ) : null,
    );
  }
}
