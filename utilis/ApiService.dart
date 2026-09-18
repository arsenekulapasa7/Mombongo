import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Requis pour HttpClient
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // Requis pour  m  IOClient
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/ConfigurationModel.dart';
import '../models/SyncronisationModel.dart';
import 'app_config.dart';
import 'auth_service.dart';

class ApiService {
  // Configuration d'un client HTTP persistant avec un timeout étendu à 3 minutes
  late final http.Client _client;

  ApiService() {
    final HttpClient baseClient = HttpClient()
      ..connectionTimeout = const Duration(minutes: 3); // Timeout de connexion
    _client = IOClient(baseClient);
  }

  /// ÉTAPE 1 : Crée le fichier de configuration avec les noms des tables.
  Future<bool> createConfigurationFile(ConfigurationModel config) async {
    final Uri urlEtape1 = Uri.parse(
      '${AppConfig.apiBaseUrl}/ConfigurationSync/SetConfiguration',
    );

    try {
      final lignesFichierTexte = config.configurationTableFile;

      Map<String, dynamic> payload = {
        "FileName": config.fileName,
        "ConfigurationTableFile": lignesFichierTexte,
      };

      print(
        "🚀 [http Envoi] Étape 1 - Envoi de "
        "${lignesFichierTexte.length} noms de tables...",
      );

      // On force le timeout à 3 minutes sur la requête
      final response = await _client
          .post(
            urlEtape1,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=UTF-8',
              'Connection': 'close',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 3));

      print("📥 [http Réponse] Étape 1 - Code : ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('api_file_created', true);
        const secureStorage = FlutterSecureStorage();
        await secureStorage.write(
          key: 'api_initialisation_complete',
          value: 'true',
        );
        return true;
      }

      return false;
    } on TimeoutException catch (e) {
      print(
        "🚨 [Timeout http Étape 1] Le serveur n'a pas répondu dans le délai "
        "attendu ($urlEtape1) : $e",
      );
      return false;
    } catch (e) {
      print("🚨 [Erreur http Étape 1] : $e");
      return false;
    }
  }

  /// ÉTAPE 2 : Lance la synchronisation avec les quatre champs API.
  Future<bool> syncAllDatabaseData(SyncModel syncData) async {
    final Uri urlEtape2 = Uri.parse(
      '${AppConfig.apiBaseUrl}/SynchronizeSync/Synchronization',
    );

    try {
      final lastSyncDate =
          syncData.lastSyncDate?.toIso8601String() ??
          await AuthService.getLastSyncDate();
      final remoteChanges = <String, List<Map<String, dynamic>>>{};
      const localOnlyColumns = {
        'is_synced',
        'magasin_uuid',
        'depot_uuid',
        'produit_uuid',
      };
      for (final entry in syncData.localChanges.entries) {
        remoteChanges[entry.key] = entry.value.map((row) {
          final remoteRow = Map<String, dynamic>.from(row);
          remoteRow.removeWhere((key, _) => localOnlyColumns.contains(key));
          return remoteRow;
        }).toList();
      }
      final Map<String, dynamic> payloadStrict = {
        "ConfigFileName": syncData.fileName,
        "ServerConnexionString": syncData.serverConnexionString,
        "LastSyncDate": lastSyncDate,
        "LocalChanges": remoteChanges,
      };

      final changedRows = syncData.localChanges.values.fold<int>(
        0,
        (total, rows) => total + rows.length,
      );
      print(
        "📤 [http Payload] Étape 2 : $changedRows ligne(s) à synchroniser.",
      );

      print(
        "🚀 [http Envoi] Étape 2 - Envoi des quatre champs de synchronisation...",
      );

      final response = await _client
          .post(
            urlEtape2,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=UTF-8',
              'Connection': 'close',
            },
            body: jsonEncode(payloadStrict),
          )
          .timeout(const Duration(minutes: 3));

      print("📥 [http Réponse] Étape 2 - Code : ${response.statusCode}");
      print("📥 [http Réponse] Étape 2 - Contenu : ${response.body}");

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await DatabaseHelper().markChangesAsSynced(syncData.localChanges);
        return true;
      }

      String serverError = response.body.trim();
      try {
        final decodedBody = jsonDecode(response.body);
        if (decodedBody is Map<String, dynamic> &&
            decodedBody['error'] is String) {
          serverError = decodedBody['error'] as String;
        }
      } on FormatException {
        // Keep the raw response when the server does not return JSON.
      }
      print(
        "🚨 [Erreur serveur Étape 2] HTTP ${response.statusCode} : "
        "$serverError",
      );
      return false;
    } on SocketException catch (e) {
      print(
        "🚨 [Erreur réseau Étape 2] Le serveur a fermé la connexion "
        "avant de répondre ($urlEtape2) : $e",
      );
      return false;
    } catch (e) {
      print("🚨 [Erreur http Étape 2] : $e");
      return false;
    }
  }
}
