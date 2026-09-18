import 'dart:convert';

class ConfigurationModel {
  final String fileName;
  final String localDb;
  final List<String> configurationTableFile;

  ConfigurationModel({
    required this.fileName,
    this.localDb = 'MaGestion.db',
    required this.configurationTableFile,
  });

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'localDb': localDb,
      'configurationTableFile': configurationTableFile,
    };
  }
}
