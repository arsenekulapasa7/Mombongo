import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/articles.dart';
import '../screens/historique_ventes.dart';
import '../utilis/auth_service.dart';
import '../models/CartItem.dart';
import 'CartPage.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    final roleRaw = await AuthService.getRole();
    final role = roleRaw.toLowerCase().trim();
    final magId = await AuthService.getMagasinId();
    final currentDepotId = await AuthService.getDepotId();
    
    List<Map<String, dynamic>> depotsCharge = [];
    if (magId != null) {
      depotsCharge = await DatabaseHelper().getDepots(magId);
    }

    if (!mounted) return;
    setState(() {
      _role = role;
      _magasinId = magId;
      _allDepots = depotsCharge;
      _selectedDepotId = (role == 'boss') ? null : currentDepotId;
      _isLoading = false;
    });
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
        title: const Text("Vente & Articles"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
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
                        onSaleConfirmed: () => setState(() => cartItems.clear()),
                      ),
                    ),
                  ).then((_) => setState(() { _refreshKey++; }));
                },
              ),
              if (cartItems.isNotEmpty)
                Positioned(right: 8, top: 8, child: CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Text("${cartItems.length}", style: const TextStyle(fontSize: 10, color: Colors.white)))),
            ],
          ),
          IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoriqueVentes()))),
        ],
      ),
      body: Column(
        children: [
          if (_role == 'boss')
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.blue.shade50,
              child: DropdownButtonFormField<int?>(
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
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey("list_$_selectedDepotId$_refreshKey"),
              future: DatabaseHelper().getProduits(_selectedDepotId, magasinId: _role == 'boss' ? _magasinId : null),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun article trouvé."));

                final filteredData = snapshot.data!.where((item) {
                  return item['nom'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                if (filteredData.isEmpty) return const Center(child: Text("Aucun résultat pour cette recherche."));

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
                        trailing: IconButton(icon: const Icon(Icons.add_shopping_cart, color: Colors.blue), onPressed: () => _addToCart(art)),
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
