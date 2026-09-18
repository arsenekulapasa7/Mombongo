import 'dart:convert';

List<Post> postFromJson(String str) =>
    List<Post>.from(json.decode(str).map((x) => Post.fromJson(x)));

class Post {
  String serverConnexionString;
  String localDb;
  String fileName;
  dynamic body; // Changé en dynamic pour éviter la double-encodage JSON

  Post({
    required this.serverConnexionString,
    required this.localDb,
    required this.fileName,
    this.body,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    serverConnexionString: json["serverConnexionString"] ?? "'magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'",
    localDb: json["localDb"] ?? "MaGestion.db",
    fileName: json["fileName"] ?? 'mombongo.text',
    body: json["body"],
  );

  Map<String, dynamic> toJson() => {
    "serverConnexionString": serverConnexionString,
    "localDb": localDb,
    "fileName": fileName,
    "body": body,
  };
}
