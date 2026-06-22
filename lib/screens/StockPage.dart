import 'package:flutter/material.dart';
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
      final found = depots.firstWhere((d) => d['idDepot'] == depId, orElse: () => {});
      if (found.isNotEmpty) nomDep = found['nomDepot'];
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
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      // 1. Exécute la synchronisation (PUSH et PULL)
      await SyncService().synchronizeData();

      // 2. RECOMPTE les éléments non synchronisés (qui devrait être 0 maintenant)
      int count = await DatabaseHelper().getUnsyncedCount();

      if (mounted) {
        setState(() {
          _unsyncedCount = count; // Mise à jour du badge à 0
          _isSyncing = false;
          _refreshKey++; // Rafraîchit la liste à l'écran
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Synchronisation réussie !"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSyncing = false);
      // ... gestion erreur ...
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

  void _ouvrirFormulaireAjout(BuildContext context) {
    final nomController = TextEditingController();
    final qteController = TextEditingController();
    final prixController = TextEditingController();

    int? targetDepotId = _selectedFilterDepotId ??
        (_allDepots.isNotEmpty ? _allDepots[0]['idDepot'] : _currentDepotId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Nouvel Article", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (_role == 'boss')
                DropdownButtonFormField<int>(
                  value: targetDepotId,
                  decoration: const InputDecoration(labelText: "Dépôt de destination"),
                  items: _allDepots.map((d) => DropdownMenuItem<int>(
                        value: d['idDepot'] as int,
                        child: Text(d['nomDepot'] as String)
                    )).toList(),
                  onChanged: (val) => setModalState(() => targetDepotId = val),
                ),
              TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom de l'article")),
              TextField(controller: qteController, decoration: const InputDecoration(labelText: "Quantité initiale"), keyboardType: TextInputType.number),
              TextField(controller: prixController, decoration: const InputDecoration(labelText: "Prix Unitaire (USD)"), keyboardType: TextInputType.number),
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
    final reapproController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Réapprovisionner ${art.nom}"),
        content: TextField(controller: reapproController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantité à ajouter")),
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
        title: const Text("Gestion du Stock"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: () => DatabaseHelper.sauvegarderBaseVersGmail(),
          ),
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
            ListTile(leading: const Icon(Icons.inventory, color: Colors.blue), title: const Text("Stock"), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.shopping_cart, color: Colors.green), title: const Text("Vendre"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const ListeArticles())); }),
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes())); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.dashboard), title: const Text("Tableau de Bord"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardPage())); }),
            if (_role == 'boss') ...[
               ListTile(leading: const Icon(Icons.add_business, color: Colors.brown), title: const Text("Nouveau Magasin"), onTap: () { Navigator.pop(context); _ouvrirNouveauMagasin(); }),
              ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.red), title: const Text("Vendeurs"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage())); }),
            ],
            ListTile(leading: const Icon(Icons.analytics), title: const Text("Rapports"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const RapportPage())); }),
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
                decoration: const InputDecoration(labelText: "Filtrer par Dépôt", border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Global (Mon Magasin)")),
                  ..._allDepots.map((d) => DropdownMenuItem(value: d['idDepot'] as int, child: Text(d['nomDepot'] as String))),
                ],
                onChanged: (val) { setState(() { _selectedFilterDepotId = val; _refreshKey++; }); },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(labelText: "Rechercher", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey("stock_$_refreshKey"),
              future: DatabaseHelper().getProduits(_selectedFilterDepotId, magasinId: _magasinId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun article."));

                final displayList = snapshot.data!.where((item) => item['nom'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();

                return ListView.builder(
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final item = displayList[index];
                    final art = Article.fromMap(item);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(art.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Prix: ${art.prix} USD | Stock: ${art.quantite}"),
                        trailing: IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => _ouvrirReappro(context, art)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade800,
        onPressed: () => _ouvrirFormulaireAjout(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
