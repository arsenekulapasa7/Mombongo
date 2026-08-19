import 'dart:convert';
import 'dart:io'; // Requis pour HttpClient
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // Requis pour IOClient
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/ConfigurationModel.dart';
import '../models/SyncronisationModel.dart';

class ApiService {
  // Configuration d'un client HTTP persistant avec un timeout étendu à 3 minutes
  late final http.Client _client;

  ApiService() {
    final HttpClient baseClient = HttpClient()
      ..connectionTimeout = const Duration(minutes: 3); // Timeout de connexion
    _client = IOClient(baseClient);
  }

  /// ÉTAPE 1 : Crée le fichier texte sur le serveur avec les données locales
  Future<bool> createConfigurationFile(ConfigurationModel config) async {
    final Uri urlEtape1 = Uri.parse('http://afrisofttech-002-site50.jtempurl.com/ConfigurationSync/SetConfiguration');

    try {
      final databasesPath = await getDatabasesPath();
      final pathDb = p.join(databasesPath, "MaGestion.db");
      final Database db = await openDatabase(pathDb);

      List<String> mesTables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
      List<String> lignesFichierTexte = ["# DEBUT"];

      for (String tableName in mesTables) {
        lignesFichierTexte.add("=== TABLE:$tableName ===");
        final List<Map<String, dynamic>> rows = await db.query(tableName);
        for (var row in rows) {
          lignesFichierTexte.add(jsonEncode(row));
        }
      }
      lignesFichierTexte.add("# FIN");

      Map<String, dynamic> payload = {
        "fileName": config.fileName,
        "configurationTableFile": lignesFichierTexte,
      };

      print("🚀 [http Envoi] Étape 1 - Envoi de ${lignesFichierTexte.length} lignes...");

      // On force le timeout à 3 minutes sur la requête
      final response = await _client.post(
        urlEtape1,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payload),
      ).timeout(const Duration(minutes: 3));

      print("📥 [http Réponse] Étape 1 - Code : ${response.statusCode}");
      return response.statusCode == 200 || response.statusCode == 201;

    } catch (e) {
      print("🚨 [Erreur http Étape 1] : $e");
      return false;
    }
  }

  /// ÉTAPE 2 : Lance la synchronisation stricte à 3 champs (Avec plus de temps)
  Future<bool> syncAllDatabaseData(SyncModel syncData) async {
    final Uri urlEtape2 = Uri.parse('http://afrisofttech-002-site50.jtempurl.com/SynchronizeSync/Synchronization');

    try {
      Map<String, dynamic> payloadStrict = {
        "serverConnexionString": syncData.serverConnexionString,
        "localDb": syncData.localDb,
        "fileName": syncData.fileName
      };

      print("🚀 [http Envoi] Étape 2 - Envoi du modèle strict à 3 champs...");

      // AJOUT DE .timeout(...) ICI pour laisser le temps au serveur C# d'écrire dans SQL Server
      final response = await _client.post(
        urlEtape2,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payloadStrict),
      ).timeout(const Duration(minutes: 3)); // 180 secondes d'attente autorisées !

      print("📥 [http Réponse] Étape 2 - Code : ${response.statusCode}");
      print("📥 [http Réponse] Étape 2 - Contenu : ${response.body}");

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final databasesPath = await getDatabasesPath();
        final pathDb = p.join(databasesPath, syncData.localDb);
        final Database db = await openDatabase(pathDb);
        List<String> mesTables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];

        await db.transaction((txn) async {
          for (String tableName in mesTables) {
            await txn.update(
              tableName,
              {'is_synced': 1},
              where: 'is_synced = ?',
              whereArgs:[0],
            );
          }
        });
        return true;
      }
      return false;

    } catch (e) {
      print("🚨 [Erreur http Étape 2] : $e");
      return false;
    }
  }
}
