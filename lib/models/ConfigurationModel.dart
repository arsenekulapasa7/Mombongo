import 'dart:convert';

class ConfigurationModel {
  final String fileName;
  final List<String> configurationTableFile;

  ConfigurationModel({
    required this.fileName,
    required this.configurationTableFile,
  });

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'configurationTableFile': configurationTableFile,
    };
  }
}
