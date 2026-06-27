import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'auth_service.dart';
import 'remote_service.dart';

class SyncService {
  final RemoteService _remoteService = RemoteService();

  /// Méthode principale de synchronisation (PUSH puis PULL)
  Future<void> synchronizeData() async {
    final int? magId = await AuthService.getMagasinId();
    if (magId == null) {
      throw Exception("ID Magasin manquant. Veuillez vous reconnecter.");
    }

    try {
      debugPrint("🔄 Début de la synchronisation globale...");

      // 1. PUSH : Envoyer les données locales vers SQL Server
      await _handlePush();

      // 2. PULL : Récupérer les nouveautés depuis SQL Server
      await _handlePull(magId);

      debugPrint("✅ Synchronisation terminée avec succès.");
    } catch (e) {
      debugPrint("🚨 Erreur critique SyncService : $e");
      rethrow; // On relance pour que l'interface affiche l'erreur
    }
  }

  /// Gère l'envoi des données locales non synchronisées
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
      // SI ECHEC DE CONNEXION PENDANT LE PUSH
      throw Exception("Le serveur est injoignable pour l'envoi des données.");
    }
  }

  /// Gère la récupération des données distantes
  Future<void> _handlePull(int magId) async {
    String lastSync = await AuthService.getLastSyncDate();
    
    // Appel au service distant
    final remoteData = await _remoteService.fetchFromCloud(magId, lastSync);

    // Si remoteData est null, c'est qu'il y a eu une erreur de connexion ou de serveur
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
