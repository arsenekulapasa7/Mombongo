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
      debugPrint("🚨 Synchronisation annulée : ID Magasin manquant");
      return;
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
      rethrow;
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
      debugPrint("ℹ️ Rien à envoyer au cloud (tout est à jour).");
      return;
    }

    bool success = await _remoteService.syncToCloud(payload);
    if (success) {
      debugPrint("📤 Données locales envoyées au cloud.");
      for (String table in payload.keys) {
        // Cette commande remet le compteur local à zéro pour chaque table
        await db.update(
            table,
            {'is_synced': 1},
            where: 'is_synced = ?',
            whereArgs: [0]
        );
      }
    }
  }

  /// Gère la récupération des données distantes
  Future<void> _handlePull(int magId) async {
    String lastSync = await AuthService.getLastSyncDate();
    Map<String, dynamic>? remoteData = await _remoteService.fetchFromCloud(magId, lastSync);

    if (remoteData != null && remoteData.isNotEmpty) {
      debugPrint("📥 Données reçues du cloud, intégration en local...");
      final db = await DatabaseHelper().database;

      await db.transaction((txn) async {
        // Correction : Utilisation de ! car remoteData est capturé dans une closure
        for (String table in remoteData!.keys) {
          final rows = remoteData![table];
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
      // Mettre à jour la date de dernière synchro réussie
      await AuthService.setLastSyncDate(DateTime.now().toIso8601String());
      debugPrint("✅ PULL réussi.");
    } else {
      debugPrint("ℹ️ Aucune nouvelle donnée distante à récupérer.");
    }
  }
}
