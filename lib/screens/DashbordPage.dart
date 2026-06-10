import 'package:flutter/material.dart';
import 'package:my_business/database/database_helper.dart';
import 'package:my_business/utilis/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // Pour décoder le JSON

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, double>> _statsFuture;
  int? _magasinId;
  int? _selectedFilterDepotId; // null = global pour le magasin (Boss)
  List<Map<String, dynamic>> _allDepots = [];
  String _role = "vendeur";

  @override
  void initState() {
    super.initState();
    _statsFuture = Future.value({'stock': 0, 'recette_jour': 0, 'recette_mois': 0});
    _initData();
  }

  void _initData() async {
    final int? magId = await AuthService.getMagasinId();
    final int? depId = await AuthService.getDepotId();
    final String role = await AuthService.getRole();
    
    if (magId == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    List<Map<String, dynamic>> depots = [];
    if (role == 'boss') {
      depots = await DatabaseHelper().getDepots(magId);
    }

    if (!mounted) return;

    setState(() {
      _magasinId = magId;
      _role = role;
      _allDepots = depots;
      _selectedFilterDepotId = (role == 'boss') ? null : depId;
      _refreshStats();
    });
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = DatabaseHelper().getStatistiques(
        _selectedFilterDepotId, 
        magasinId: _magasinId
      );
    });
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshStats),
        ],
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
        color: color.withOpacity(0.1), // Correction : withOpacity au lieu de withValues pour compatibilité
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
