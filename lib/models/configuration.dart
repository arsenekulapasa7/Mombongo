import 'dart:convert';

class Config {
  String configurationTableFile;
  String fileName;
  String? body;
  String apiUrl;

  Config({
    required this.configurationTableFile,
    this.fileName = 'mombongo.text',
    this.body,
    required this.apiUrl,
  });

  factory Config.fromJson(Map<String, dynamic> json) => Config(
        configurationTableFile: json["configurationTableFile"] ?? "'magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'",
        fileName: json["filename"] ?? "mombongo.text",
        body: json["body"],
        apiUrl: json["apiUrl"] ?? "http://afrisofttech-002-site50.jtempurl.com/",
      );

  Map<String, dynamic> toJson() => {
        "configurationTableFile": configurationTableFile,
        "filename": fileName,
        "body": body,
        "apiUrl": apiUrl,
      };
}
