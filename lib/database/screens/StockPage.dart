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
  int? _selectedFilterDepotId; // null = global pour le boss
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

    final db = await DatabaseHelper().database;
    String nomDep = "Mon Dépôt";

    if (depId != null) {
      List<Map<String, dynamic>> depRes = await db.query(
        'depots', 
        where: 'idDepot = ? AND magasin_id = ?', 
        whereArgs: [depId, magId]
      );
      
      if (depRes.isNotEmpty) {
        nomDep = depRes.first['nomDepot'];
      }
    }

    List<Map<String, dynamic>> depots = await DatabaseHelper().getDepots(magId);

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


  Future<void> _checkUnsynced() async { // <--- Changez void en Future<void>
    int count = await DatabaseHelper().getUnsyncedCount();
    if (mounted) {
      setState(() { _unsyncedCount = count; });
    }
  }

  void _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Synchronisation en cours..."), duration: Duration(seconds: 1)),
    );

    await DatabaseHelper().syncAllLocalToServer();
    // On peut aussi faire un pull après le push
    // await DatabaseHelper().fetchAllFromServer(await AuthService.getLastSyncDate());
    
    _checkUnsynced();
    setState(() => _isSyncing = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Synchronisation terminée"), backgroundColor: Colors.green),
      );
      setState(() { _refreshKey++; });
    }
  }

  Future<bool?> _confirmDelete(Article art) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer l'article"),
        content: Text("Voulez-vous vraiment supprimer ${art.nom} ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Supprimer", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  void _deleteArticle(Article art) async {
    if (art.id != null) {
      await DatabaseHelper().deleteProduit(art.id!);
      _checkUnsynced();
      if (!mounted) return;
      setState(() { _refreshKey++; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${art.nom} supprimé")));
    }
  }
  // Variable pour stocker le nombre d'éléments non sync

  // La fonction qui manque et qui cause l'erreur rouge :

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
              left: 20,
              right: 20,
              top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Nouvel Article", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

              if (_role == 'boss')
                DropdownButtonFormField<int>(
                  initialValue: targetDepotId,
                  decoration: const InputDecoration(labelText: "Dépôt de destination"),
                  items: _allDepots.map((d) {
                    return DropdownMenuItem<int>(
                        value: d['idDepot'] as int,
                        child: Text(d['nomDepot'] as String)
                    );
                  }).toList(),
                  onChanged: (val) {
                    setModalState(() => targetDepotId = val);
                  },
                ),

              TextField(
                controller: nomController,
                decoration: const InputDecoration(labelText: "Nom de l'article"),
              ),
              TextField(
                controller: qteController,
                decoration: const InputDecoration(labelText: "Quantité initiale"),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: prixController,
                decoration: const InputDecoration(labelText: "Prix Unitaire (USD)"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45)),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  if (targetDepotId == null || nomController.text.trim().isEmpty) {
                    messenger.showSnackBar(const SnackBar(content: Text("Remplissez tous les champs")));
                    return;
                  }

                  final nouveauProduit = {
                    'nom': nomController.text,
                    'quantite': int.tryParse(qteController.text) ?? 0,
                    'prix_unitaire': double.tryParse(prixController.text) ?? 0.0,
                  };

                  await DatabaseHelper().insertProduit(nouveauProduit, targetDepotId!);
                  _checkUnsynced();

                  if (!mounted) return;
                  navigator.pop();
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
        content: TextField(
          controller: reapproController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Quantité à ajouter",
            suffixText: "pcs",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              int qte = int.tryParse(reapproController.text) ?? 0;
              if (qte > 0) {
                int? depotId = art.depotId ?? _selectedFilterDepotId ?? _currentDepotId;
                if (depotId != null) {
                  await DatabaseHelper().reaprovisionner(art.id!, qte, depotId);
                  _checkUnsynced();
                  if (!mounted) return;
                  navigator.pop();
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

  void _ouvrirGestionDepots() {
    final depotController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nouveau Dépôt"),
        content: TextField(
          controller: depotController,
          decoration: const InputDecoration(labelText: "Nom du Dépôt"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (depotController.text.isNotEmpty && _magasinId != null) {
                await DatabaseHelper().addDepot(depotController.text, _magasinId!);
                _checkUnsynced();
                if (!mounted) return;
                _loadUserData(); 
                navigator.pop();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestion du Stock"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt), // Icône de téléchargement/sauvegarde
            tooltip: "Sauvegarder la base de données",
            onPressed: () async {
              await DatabaseHelper.sauvegarderBaseVersGmail();
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [

              IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Icon(Icons.cloud_upload),
                onPressed: _isSyncing
                    ? null
                    : () async {
                  setState(() => _isSyncing = true);
                  try {
                    // 1. Exécuter la synchronisation
                    await SyncService().synchronizeData();

                    // 2. IMPORTANT : Mettre à jour le compteur de badge
                    await _checkUnsynced();

                    // 3. Recharger les données locales
                    _loadUserData();

                    if (mounted) {
                      setState(() {
                        _isSyncing = false;
                        _refreshKey++;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Synchronisation réussie !")),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isSyncing = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ), // Fin de l'IconButton
              if (_unsyncedCount > 0 && !_isSyncing)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_unsyncedCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warehouse, color: Colors.white, size: 40),
                  const SizedBox(height: 10),
                  Text(_nomDepot, style: const TextStyle(color: Colors.white, fontSize: 24)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inventory, color: Colors.blue),
              title: const Text("Stock"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart, color: Colors.green),
              title: const Text("Vendre"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ListeArticles()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.orange),
              title: const Text("Historique des Ventes"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text("Tableau de Bord"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardPage()));
              },
            ),
            if (_role == 'boss') ...[
              ListTile(
                leading: const Icon(Icons.add_business, color: Colors.brown),
                title: const Text("Nouveau Dépôt"),
                onTap: () {
                  Navigator.pop(context);
                  _ouvrirGestionDepots();
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.red),
                title: const Text("Gestion des Vendeurs"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage()));
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text("Rapports"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RapportPage()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.grey),
              title: const Text("Déconnexion"),
              onTap: () async {
                final navigator = Navigator.of(context);
                bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Déconnexion"),
                    content: const Text("Voulez-vous vraiment vous déconnecter ?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Oui", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await AuthService.logout();
                  if (!mounted) return;
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                }
              },
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
                onChanged: (val) {
                   setState(() {
                      _selectedFilterDepotId = val;
                      _refreshKey++;
                   });
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                labelText: "Rechercher un article",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey("stock_list_$_refreshKey"),
              future: DatabaseHelper().getProduits(_selectedFilterDepotId, magasinId: _magasinId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun article trouvé."));

                final displayList = snapshot.data!.where((item) {
                  return item['nom'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                if (displayList.isEmpty) return const Center(child: Text("Aucun résultat pour cette recherche."));

                return ListView.builder(
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final item = displayList[index];
                    final art = Article.fromMap(item);
                    
                    final card = Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(art.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Dépôt: ${item['nomDepot'] ?? 'N/A'}\nPrix: ${art.prix} USD"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Stock: ${art.quantite}"),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                              onPressed: () => _ouvrirReappro(context, art),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (_role == 'boss') {
                      return Dismissible(
                        key: ValueKey("del_stock_${art.id}_${item['depot_id']}"),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red, 
                          alignment: Alignment.centerRight, 
                          padding: const EdgeInsets.only(right: 20), 
                          child: const Icon(Icons.delete, color: Colors.white)
                        ),
                        confirmDismiss: (_) => _confirmDelete(art),
                        onDismissed: (_) => _deleteArticle(art),
                        child: card,
                      );
                    }
                    return card;
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
