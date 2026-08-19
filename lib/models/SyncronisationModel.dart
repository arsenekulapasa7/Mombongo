// Fichier : models/SyncronisationModel.dart
class SyncModel {
  final String serverConnexionString;
  final String localDb;
  final String fileName;

  SyncModel({
    required this.serverConnexionString,
    required this.localDb,
    required this.fileName,
  });

  Map<String, dynamic> toJson() {
    return {
      'serverConnexionString': serverConnexionString,
      'localDb': localDb,
      'fileName': fileName,
    };
  }
}
