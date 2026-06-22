import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utilis/pdf_service.dart';
import '../utilis/auth_service.dart';
import 'package:intl/intl.dart';
import '../utilis/sync_service.dart';
import 'StockPage.dart';
import 'liste_articles.dart';
import 'DashbordPage.dart';
import 'RapportPage.dart';
import 'UserManagementPage.dart';
import 'login_page.dart';

class HistoriqueVentes extends StatefulWidget {
  const HistoriqueVentes({super.key});

  @override
  State<HistoriqueVentes> createState() => _HistoriqueVentesState();
}

class _HistoriqueVentesState extends State<HistoriqueVentes> {
  String _dateFiltre = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _searchQuery = "";
  late Future<List<Map<String, dynamic>>> _ventesFuture;
  final TextEditingController _searchController = TextEditingController();
  int? _currentDepotId;
  int? _magasinId;
  String _nomDepot = "Mon Point de Vente";
  int? _selectedFilterDepotId; 
  List<Map<String, dynamic>> _allDepots = [];
  String _role = "vendeur";
  
  // Variables pour la synchronisation
  bool _isSyncing = false;
  int _unsyncedCount = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _ventesFuture = Future.value([]);
    _initData();
    _checkUnsynced();
  }

  void _initData() async {
    final magId = await AuthService.getMagasinId();
    final depId = await AuthService.getDepotId();
    final role = await AuthService.getRole();

    if (magId == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
      return;
    }

    final List<Map<String, dynamic>> depots = await DatabaseHelper().getDepots(magId);
    
    String nomDep = "Mon Point de Vente";
    if (depId != null) {
      final found = depots.firstWhere((d) => d['idDepot'] == depId, orElse: () => {});
      if (found.isNotEmpty) nomDep = found['nomDepot'];
    }

    if (!mounted) return;

    setState(() {
      _magasinId = magId;
      _currentDepotId = depId;
      _nomDepot = nomDep;
      _role = role;
      _allDepots = depots;
      _selectedFilterDepotId = (role == 'boss') ? null : depId;
      _chargerDonnees();
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
      _chargerDonnees();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _refreshKey++; 
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Historique synchronisé !"), backgroundColor: Colors.green),
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
                _initData();
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _chargerDonnees() {
    setState(() {
      _ventesFuture = DatabaseHelper().getVentesParDate(
        _dateFiltre, 
        _selectedFilterDepotId, 
        magasinId: _magasinId
      );
    });
  }

  void _imprimerHistorique() async {
    final rawList = await _ventesFuture;
    final filteredList = rawList.where((vente) {
      final nomP = (vente['nom_produit'] ?? "").toString().toLowerCase();
      final nomC = (vente['nom_client'] ?? "").toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return nomP.contains(q) || nomC.contains(q);
    }).toList();
    
    if (filteredList.isEmpty) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucune donnée à imprimer")));
       return;
    }
    
    await PdfService.imprimerJournalVentes(filteredList, _dateFiltre.isEmpty ? "Global" : _dateFiltre);
  }

  void _afficherFacture(Map<String, dynamic> vente) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Text(_nomDepot, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const Text("Facture de Vente", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const Divider(),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Date: ${vente['date_vente'].toString().substring(0, 16).replaceAll('T', ' ')}"),
            Text("Client: ${vente['nom_client'] ?? 'Non précisé'}"),
            const SizedBox(height: 10),
            Text("Produit: ${vente['nom_produit']}", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Quantité: ${vente['quantite_vendue']}"),
            const Divider(),
            Text("TOTAL: ${vente['prix_total']} USD", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer", style: TextStyle(color: Colors.red))),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text("Imprimer"),
            onPressed: () => PdfService.genererFacture(vente),
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
        title: const Text("Journal des Ventes"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _imprimerHistorique,
            tooltip: "Imprimer l'historique",
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
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
              );
              if (pickedDate != null) {
                setState(() {
                  _dateFiltre = DateFormat('yyyy-MM-dd').format(pickedDate);
                  _chargerDonnees();
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.all_inclusive),
            onPressed: () {
              setState(() {
                _dateFiltre = "";
                _chargerDonnees();
              });
            },
          )
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
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () => Navigator.pop(context)),
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
                    _chargerDonnees();
                  });
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: "Chercher un produit ou un client...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = "");
                    }) 
                  : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey("ventes_list_$_refreshKey"),
              future: _ventesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
                
                final rawList = snapshot.data ?? [];
                if (rawList.isEmpty) return const Center(child: Text("Aucune vente trouvée."));

                final filteredList = rawList.where((vente) {
                  final nomP = (vente['nom_produit'] ?? "").toString().toLowerCase();
                  final nomC = (vente['nom_client'] ?? "").toString().toLowerCase();
                  final q = _searchQuery.toLowerCase();
                  return nomP.contains(q) || nomC.contains(q);
                }).toList();

                double total = filteredList.fold(0, (sum, item) => sum + ((item['prix_total'] as num?)?.toDouble() ?? 0.0));

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.blue.shade50,
                      child: Text(
                        "Total : ${NumberFormat.decimalPattern('fr_FR').format(total)} USD",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                      ),
                    ),
                    Expanded(
                      child: filteredList.isEmpty
                          ? const Center(child: Text("Aucun résultat pour cette recherche"))
                          : ListView.builder(
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final vente = filteredList[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(Icons.receipt_long, color: Colors.green),
                                    title: Text(vente['nom_produit'] ?? "Produit", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text("${vente['nom_client'] ?? 'Divers'} - ${vente['date_vente'].toString().substring(0, 10)}"),
                                    onTap: () => _afficherFacture(vente),
                                    trailing: Text("${vente['prix_total']} USD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
