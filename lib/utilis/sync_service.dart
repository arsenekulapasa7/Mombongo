import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'auth_service.dart';
import 'remote_service.dart';
import '../models/ConfigurationModel.dart';
import '../models/SyncronisationModel.dart';
import 'package:http/http.dart' as http;

class SyncService {
  final RemoteService _remoteService = RemoteService();

  /// Envoie les données de configuration réseau.
  /// Lève une Exception en cas d'échec HTTP ou d'erreur réseau.


  Future<void> syncDataBase(Map<String, dynamic> dataToSync) async {
    // 1. Remplacez par le endpoint EXACT trouvé sur votre Swagger UI
    final Uri url = Uri.parse("");

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
          "Accept": "application/json",
        },
        body: jsonEncode(dataToSync),
      );

      // Diagnostic précis en cas de persistance de l'erreur 404
      if (response.statusCode == 404) {
        print("Erreur 404 sur l'URL : $url");
        print("Le serveur répond : ${response.body}");
        throw Exception("Route introuvable. Vérifiez l'orthographe exacte et les majuscules.");
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }

      print("✅ Synchronisation réussie !");
    } catch (e) {
      throw Exception("Échec de la synchronisation : $e");
    }
  }


  Future<void> _handlePush() async {
    final List<String> tables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
    final db = await DatabaseHelper().database;
    Map<String, List<Map<String, dynamic>>> payload = {};

    for (String table in tables) {
      List<Map<String, dynamic>> unsynced = await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
      if (unsynced.isNotEmpty) {
        payload[table] = unsynced;
      }
    }

    if (payload.isEmpty) {
      debugPrint("ℹ️ Rien à envoyer au cloud.");
      return;
    }

    bool success = await _remoteService.syncToCloud(payload);
    if (success) {
      debugPrint("📤 Données locales envoyées au cloud.");
      for (String table in payload.keys) {
        await db.update(
            table,
            {'is_synced': 1},
            where: 'is_synced = ?',
            whereArgs: [0]
        );
      }
    } else {
      throw Exception("Le serveur est injoignable pour l'envoi des données.");
    }
  }

  Future<bool> createConfigurationFile(ConfigurationModel config) async {
    final Uri url = Uri.parse('http://afrisofttech-002-site50.jtempurl.com/ConfigurationSync/SetConfiguration');
    try {
      final response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(config.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('Fichier créé avec succès sur le serveur.');
        return true;
      } else {
        print('Erreur serveur : ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Une erreur réseau est survenue : $e');
      return false;
    }
  }

  Future<void> _handlePull(int magId) async {
    String lastSync = await AuthService.getLastSyncDate();
    final remoteData = await _remoteService.fetchFromCloud(magId, lastSync);

    if (remoteData == null) {
      throw Exception("Le serveur est injoignable pour la récupération des données.");
    }

    if (remoteData.isNotEmpty) {
      debugPrint("📥 Données reçues du cloud, intégration en local...");
      final db = await DatabaseHelper().database;
      await db.transaction((txn) async {
        for (String table in remoteData.keys) {
          final rows = remoteData[table];
          if (rows is List) {
            for (var row in rows) {
              if (row is Map<String, dynamic>) {
                await txn.insert(
                    table,
                    {...row, 'is_synced': 1},
                    conflictAlgorithm: ConflictAlgorithm.replace
                );
              }
            }
          }
        }
      });
      await AuthService.setLastSyncDate(DateTime.now().toIso8601String());
      debugPrint("✅ PULL réussi.");
    } else {
      debugPrint("ℹ️ Aucune nouvelle donnée distante à récupérer.");
    }
  }
}
