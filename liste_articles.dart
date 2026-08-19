import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/ConfigurationModel.dart';
import '../models/SyncronisationModel.dart';
import '../models/articles.dart';
import 'historique_ventes.dart';
import '../utilis/auth_service.dart';
import '../models/CartItem.dart';
import 'CartPage.dart';
import '../utilis/sync_service.dart';
import 'StockPage.dart';
import 'DashbordPage.dart';
import 'RapportPage.dart';
import 'UserManagementPage.dart';
import 'login_page.dart';
import '../models/configuration.dart';
import 'package:http/http.dart' as http;
import '../utilis/ApiService.dart';

class ListeArticles extends StatefulWidget {
  const ListeArticles({super.key});

  @override
  State<ListeArticles> createState() => _ListeArticlesState();
}

class _ListeArticlesState extends State<ListeArticles> {
  String _searchQuery = "";
  List<CartItem> cartItems = [];
  int? _selectedDepotId;
  int? _magasinId;
  String _role = "";
  List<Map<String, dynamic>> _allDepots = [];
  bool _isLoading = true;
  int _refreshKey = 0;
  int _unsyncedCount = 0;
  bool _isSyncing = false;
  String fileName = "config.txt";
  List<String> configurationTableFile =['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
  String serverConnexionString = "Data Source=SQL5083.site4now.net;Initial Catalog=db_a54efd_synchronizedb;"
      "User Id=db_a54efd_synchronizedb_admin;Password=12345678GL;Encrypt=True;TrustServerCertificate=True";
  String localDb = "MaGestion.db";
  bool _isFileCreated = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkUnsynced();
  }

  void _loadUserData() async {
    final roleRaw = await AuthService.getRole();
    final role = roleRaw.toLowerCase().trim();
    final magId = await AuthService.getMagasinId();
    final currentDepotId = await AuthService.getDepotId();

    if (magId == null) return;

    List<Map<String, dynamic>> depotsCharge = await DatabaseHelper().getDepots(magId);

    if (!mounted) return;
    setState(() {
      _role = role;
      _magasinId = magId;
      _allDepots = depotsCharge;
      _selectedDepotId = (role == 'boss') ? null : currentDepotId;
      _isLoading = false;
    });
  }

  Future<void> _checkUnsynced() async {
    int count = await DatabaseHelper().getUnsyncedCount();
    if (mounted) setState(() => _unsyncedCount = count);
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
  // Fonction utilitaire pour afficher les notifications à l'utilisateur
  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _addToCart(Article art) {
    if (art.quantite <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stock épuisé !"), backgroundColor: Colors.red));
      return;
    }
    final idx = cartItems.indexWhere((item) => item.article.id == art.id);
    setState(() {
      if (idx == -1) {
        cartItems.add(CartItem(article: art, quantity: 1));
      } else {
        if (cartItems[idx].quantity < art.quantite) {
          cartItems[idx].quantity++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Limite de stock atteinte")));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vente Articles"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.blueGrey, strokeWidth: 2),
                )
                    : const Icon(Icons.cloud_upload),
                onPressed: _isSyncing
                    ? null
                    : () async {
                  setState(() => _isSyncing = true);

                  try {
                    final apiService = ApiService();
                    String nomDuFichier = "config_tables.txt";

                    // =========================================================
                    // EXÉCUTION COMMANDE 2 UNIQUEMENT : Synchronisation Directe
                    // =========================================================
                    SyncModel monSyncModel = SyncModel(
                      serverConnexionString: "Data Source=SQL5083.site4now.net;Initial Catalog=db_a54efd_synchronizedb;User Id=db_a54efd_synchronizedb_admin;Password=12345678GL;Encrypt=True;TrustServerCertificate=True",
                      localDb: "MaGestion.db",
                      fileName: nomDuFichier,
                    );

                    _showSnackBar(context, "🔄 Lancement de la synchronisation des données...", Colors.blue);

                    // Appelle uniquement l'étape 2 (qui utilise le JSON strict à 3 champs)
                    bool isSuccess = await apiService.syncAllDatabaseData(monSyncModel);

                    if (!mounted) return;

                    if (isSuccess) {
                      setState(() {
                        _refreshKey++; // Incrémente la clé pour vider et rafraîchir l'écran
                      });
                      _showSnackBar(context, "✅ Base de données entièrement synchronisée !", Colors.green);
                    } else {
                      _showSnackBar(context, "🚨 Échec de la synchronisation (Regardez la console).", Colors.red);
                    }

                  } catch (e) {
                    print("🚨 Erreur d'exécution du bouton : $e");
                    if (mounted) {
                      _showSnackBar(context, "🚨 Erreur système lors de la synchronisation.", Colors.red);
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSyncing = false);
                    }
                  }
                },
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
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.greenAccent, size: 28),
                onPressed: cartItems.isEmpty ? null : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CartPage(
                        cartItems: cartItems,
                        depotId: _selectedDepotId ?? 0,
                        onSaleConfirmed: () {
                          setState(() => cartItems.clear());
                          _checkUnsynced();
                        },
                      ),
                    ),
                  ).then((_) {
                    setState(() { _refreshKey++; });
                    _checkUnsynced();
                  });
                },
              ),
              if (cartItems.isNotEmpty)
                Positioned(right: 8, top: 8, child: CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Text("${cartItems.length}", style: const TextStyle(fontSize: 10, color: Colors.white)))),
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

            ListTile(leading: const Icon(Icons.shopping_cart, color: Colors.green), title: const Text("Vendre"), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: const Text("Historique"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes())); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.dashboard), title: const Text("Tableau de Bord"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardPage())); }),
            if (_role == 'boss') ...[
              ListTile(leading: const Icon(Icons.inventory, color: Colors.blue), title: const Text("Stock"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const StockPage())); }),
              ListTile(leading: const Icon(Icons.add_business, color: Colors.brown), title: const Text("Nouveau Magasin"), onTap: () { Navigator.pop(context); _ouvrirNouveauMagasin(); }),
              ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.red), title: const Text("Vendeurs"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementPage())); }),
            ],
            ListTile(leading: const Icon(Icons.analytics), title: const Text("Rapports"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const RapportPage())); }),
            ListTile(
              leading: Icon(
                Icons.settings,
                color: _isFileCreated ? Colors.grey : Colors.blueGrey,
              ),
              title: Text(
                _isFileCreated ? "API configurée (Fichier créé)" : "Configuration API",
                style: TextStyle(color: _isFileCreated ? Colors.grey : null),
              ),
              onTap: _isFileCreated
                  ? null
                  : () async {
                Navigator.pop(context); // Ferme le menu latéral

                final apiService = ApiService();
                String nomDuFichier = "config_tables.txt";

                ConfigurationModel modelConfig = ConfigurationModel(
                  fileName: nomDuFichier,
                  configurationTableFile: ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'],
                );

                _showSnackBar(context, "🔄 Étape 1 : Création du fichier sur le serveur...", Colors.blue);

                // Exécute SEULEMENT la commande 1
                bool isConfigSaved = await apiService.createConfigurationFile(modelConfig);

                if (!context.mounted) return;

                if (isConfigSaved) {
                  _showSnackBar(context, "✅ Fichier de configuration créé avec succès !", Colors.green);

                  // Sauvegarde de l'état pour bloquer le bouton définitivement
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('api_file_created', true);

                  setState(() {
                    _isFileCreated = true;
                  });
                } else {
                  _showSnackBar(context, "🚨 Échec : Impossible de créer le fichier texte sur le serveur.", Colors.red);
                }
              },
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
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.blue.shade50,
              child: DropdownButtonFormField<int?>(
                key: ValueKey("dep_sel_venta_$_selectedDepotId"),
                value: _selectedDepotId,
                decoration: const InputDecoration(labelText: "Filtrer par dépôt", border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Tous les dépôts (Vue Entreprise)")),
                  ..._allDepots.map((d) => DropdownMenuItem<int>(value: d['idDepot'], child: Text(d['nomDepot']))),
                ],
                onChanged: (val) => setState(() { _selectedDepotId = val; _refreshKey++; }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(labelText: "Rechercher un article", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              // Utilisation d'une fonction anonyme directe pour incrémenter la clé de rafraîchissement
              onRefresh: () async {
                setState(() {
                  _refreshKey++; // Change la valeur pour forcer le FutureBuilder à se relancer
                });
                // Optionnel : Un léger délai pour laisser l'animation du RefreshIndicator se terminer proprement
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: FutureBuilder<List<Map<String, dynamic>>>(
                // La clé écoute _refreshKey. Si elle change, tout le bloc ci-dessous se recharge
                key: ValueKey("list_venta_$_selectedDepotId$_refreshKey"),
                future: DatabaseHelper().getProduits(_selectedDepotId, magasinId: _magasinId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("Aucun article trouvé."));
                  }

                  final filteredData = snapshot.data!.where((item) {
                    return item['nom'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
                  }).toList();

                  return ListView.builder(
                    itemCount: filteredData.length,
                    itemBuilder: (context, index) {
                      final item = filteredData[index];
                      final art = Article.fromMap(item);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          title: Text(art.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Dépôt: ${item['nomDepot'] ?? 'N/A'}\nPrix: ${art.prix} USD | Stock: ${art.quantite}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_shopping_cart, color: Colors.blue),
                            onPressed: () => _addToCart(art),
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