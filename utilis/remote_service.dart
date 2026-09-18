import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/post.dart';
import 'app_config.dart';

class RemoteService {
  // Correction : L'URL doit pointer vers l'endpoint complet
  final String _apiUrl = "${AppConfig.apiBaseUrl}/api/posts";

  /// PUSH : Envoie les données vers SQL Server via le modèle Post
  Future<bool> syncToCloud(Map<String, dynamic> dataPayload) async {
    try {
      // On utilise 'MaGestion.db' qui est le nom défini dans DatabaseHelper
      Post post = Post(
        serverConnexionString: AppConfig.sqlConnectionString,
        localDb: 'MaGestion.db',
        fileName: 'MaGestion.db', // Cohérence avec votre DatabaseHelper
        body: dataPayload, // On passe l'objet directement (pas de double jsonEncode)
      );

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(post.toJson()),
      ).timeout(const Duration(seconds: 30));

      print("📡 Status Envoi: ${response.statusCode}");
      return (response.statusCode == 200 || response.statusCode == 201);
    } catch (e) {
      print("🚨 Erreur Connexion Cloud : $e");
      return false;
    }
  }

  /// PULL : Récupère les données depuis le serveur
  Future<Map<String, dynamic>?> fetchFromCloud(int magasinId, String since) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.apiBaseUrl}/api/sync/pull?magasin_id=$magasinId&since=$since"),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print("🚨 Erreur Réception Cloud : $e");
      return null;
    }
  }
}