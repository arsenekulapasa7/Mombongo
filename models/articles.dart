class Article {
  final int? id;
  final String nom;
  final int quantite;
  final double prix;
  final int? depotId; // Ajout du depotId

  Article({
    this.id, 
    required this.nom, 
    required this.quantite, 
    required this.prix,
    this.depotId,
  });

  // Convertit un résultat de la base de données (Map) en objet Article
  factory Article.fromMap(Map<String, dynamic> json) => Article(
    id: json['id'],
    nom: json['nom'],
    quantite: json['quantite'],
    prix: (json['prix_unitaire'] as num).toDouble(),
    depotId: json['depot_id'], // Récupération du depot_id
  );

  // Convertit un objet Article en Map pour l'insertion en base de données
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'quantite': quantite,
      'prix_unitaire': prix,
      'depot_id': depotId,
    };
  }
}
