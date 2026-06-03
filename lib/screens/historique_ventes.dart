import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utilis/pdf_service.dart';
import '../utilis/auth_service.dart';
import 'package:intl/intl.dart';

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
  int? _selectedFilterDepotId; // null = global pour le magasin (Boss)
  List<Map<String, dynamic>> _allDepots = [];
  String _role = "vendeur";

  @override
  void initState() {
    super.initState();
    // Initialisation par défaut pour éviter l'erreur late initialization
    _ventesFuture = Future.value([]);
    _initData();
  }

  void _initData() async {
    final magId = await AuthService.getMagasinId();
    final depId = await AuthService.getDepotId();
    final role = await AuthService.getRole();

    if (magId == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    // Récupérer le nom du dépôt actuel
    String nomDep = "Mon Point de Vente";
    final db = await DatabaseHelper().database;
    
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

    List<Map<String, dynamic>> depots = [];
    if (role == 'boss') {
      depots = await DatabaseHelper().getDepots(magId);
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
