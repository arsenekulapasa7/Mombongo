import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/CartItem.dart';
import '../utilis/pdf_service.dart';

class CartPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final int depotId;
  final VoidCallback onSaleConfirmed;

  const CartPage({
    super.key,
    required this.cartItems,
    required this.depotId,
    required this.onSaleConfirmed,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final TextEditingController clientController = TextEditingController(text: "Client Divers");
  bool _isLoading = false;

  @override
  void dispose() {
    clientController.dispose();
    super.dispose();
  }

  double get total => widget.cartItems.fold(0.0, (sum, item) => sum + (item.article.prix * item.quantity));

  void _confirmSale() async {
    if (widget.cartItems.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);

    try {
      // DatabaseHelper().validerPanier(items, nomClient, depotId)
      bool success = await DatabaseHelper().validerPanier(
        widget.cartItems,
        clientController.text,
        widget.depotId,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        // Préparer les données pour l'impression de la facture
        final Map<String, dynamic> venteInfo = {
          'date_vente': DateTime.now().toIso8601String(),
          'nom_client': clientController.text,
          'depot_id': widget.depotId,
        };

        final List<Map<String, dynamic>> details = widget.cartItems.map((item) => {
          'nom_produit': item.article.nom,
          'quantite_vendue': item.quantity,
          'prix_total': item.article.prix * item.quantity,
        }).toList();

        // Lancer l'impression (Ouvre la boîte de dialogue système)
        try {
          await PdfService.genererFacture(venteInfo, details: details);
        } catch (e) {
          debugPrint("Erreur lors de l'impression : $e");
          // On continue quand même car la vente est validée en DB
        }

        widget.onSaleConfirmed();
        messenger.showSnackBar(
          const SnackBar(content: Text("Vente enregistrée avec succès !"), backgroundColor: Colors.green),
        );
        navigator.pop();
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Erreur : Stock insuffisant ou problème de base de données"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Erreur inattendue : $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Finaliser la vente"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.cartItems.isEmpty
                ? const Center(child: Text("Le panier est vide"))
                : ListView.builder(
                    itemCount: widget.cartItems.length,
                    itemBuilder: (context, index) {
                      final item = widget.cartItems[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          title: Text(item.article.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "${item.article.prix} USD x ${item.quantity} = ${(item.article.prix * item.quantity).toStringAsFixed(2)} USD"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                                onPressed: () {
                                  setState(() {
                                    if (item.quantity > 1) {
                                      item.quantity--;
                                    } else {
                                      widget.cartItems.removeAt(index);
                                    }
                                  });
                                },
                              ),
                              Text("${item.quantity}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                onPressed: () {
                                  if (item.quantity < item.article.quantite) {
                                    setState(() {
                                      item.quantity++;
                                    });
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text("Stock max atteint"), duration: Duration(seconds: 1)));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 10, spreadRadius: 1)],
            ),
            child: Column(
              children: [
                TextField(
                  controller: clientController,
                  decoration: const InputDecoration(
                    labelText: "Nom du client",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total à payer :", style: TextStyle(fontSize: 18)),
                    Text("${total.toStringAsFixed(2)} USD",
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: _isLoading ? null : _confirmSale,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("VALIDER LA VENTE", style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
