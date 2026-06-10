import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../models/CartItem.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utilis/auth_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  final String _apiUrl = "http://afrisofttech-002-site50.jtempurl.com";

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'MaGestion.db');
    return await openDatabase(
      path,
      version: 19, 
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 19) {
          await db.execute('DROP TABLE IF EXISTS mouvements');
          await db.execute('DROP TABLE IF EXISTS ventes');
          await db.execute('DROP TABLE IF EXISTS produits');
          await db.execute('DROP TABLE IF EXISTS utilisateurs');
          await db.execute('DROP TABLE IF EXISTS depots');
          await db.execute('DROP TABLE IF EXISTS magasins');
          await _onCreate(db, newVersion);
        }
      },
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE magasins (idMagasin INTEGER PRIMARY KEY AUTOINCREMENT, nomMagasin TEXT NOT NULL UNIQUE, is_synced INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE depots (idDepot INTEGER PRIMARY KEY AUTOINCREMENT, nomDepot TEXT NOT NULL, magasin_id INTEGER NOT NULL, is_synced INTEGER DEFAULT 0, FOREIGN KEY (magasin_id) REFERENCES magasins (idMagasin) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE produits (id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL COLLATE NOCASE, quantite INTEGER DEFAULT 0, prix_unitaire REAL DEFAULT 0.0, depot_id INTEGER, is_synced INTEGER DEFAULT 0, FOREIGN KEY (depot_id) REFERENCES depots (idDepot) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE ventes (id INTEGER PRIMARY KEY AUTOINCREMENT, id_transaction TEXT, produit_id INTEGER, nom_produit TEXT, nom_client TEXT, quantite_vendue INTEGER, prix_total REAL, date_vente TEXT, depot_id INTEGER, is_synced INTEGER DEFAULT 0, FOREIGN KEY (depot_id) REFERENCES depots (idDepot) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE mouvements (id INTEGER PRIMARY KEY AUTOINCREMENT, produit_id INTEGER, nom_produit TEXT, quantite INTEGER, type TEXT, date_mouvement TEXT, depot_id INTEGER, is_synced INTEGER DEFAULT 0, FOREIGN KEY (depot_id) REFERENCES depots (idDepot) ON DELETE CASCADE)');
    await db.execute('''CREATE TABLE utilisateurs (
      idUser INTEGER PRIMARY KEY AUTOINCREMENT, 
      nomUser TEXT NOT NULL UNIQUE COLLATE NOCASE, 
      motDePasse TEXT NOT NULL, 
      niveauUser TEXT NOT NULL, 
      UserState INTEGER DEFAULT 0, 
      magasin_id INTEGER NOT NULL, 
      depot_id INTEGER, 
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (magasin_id) REFERENCES magasins (idMagasin) ON DELETE CASCADE, 
      FOREIGN KEY (depot_id) REFERENCES depots (idDepot) ON DELETE SET NULL
    )''');
    await db.execute("CREATE INDEX idx_magasin_depots ON depots (magasin_id)");
    await db.execute("CREATE INDEX idx_magasin_users ON utilisateurs (magasin_id)");
    await db.execute("CREATE INDEX idx_prod_depot ON produits (depot_id)");
  }

  // --- SYNCHRONISATION ---
  Future<int> getUnsyncedCount() async {
    Database db = await database;
    int count = 0;
    final List<String> tables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
    for (String table in tables) {
      var res = await db.rawQuery('SELECT COUNT(*) as total FROM $table WHERE is_synced = 0');
      count += Sqflite.firstIntValue(res) ?? 0;
    }
    return count;
  }

  Future<bool> syncAllLocalToServer() async {
    final List<String> tables = ['magasins', 'depots', 'produits', 'utilisateurs', 'ventes', 'mouvements'];
    Database db = await database;
    Map<String, List<Map<String, dynamic>>> payload = {};
    for (String table in tables) {
      List<Map<String, dynamic>> unsynced = await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
      if (unsynced.isNotEmpty) payload[table] = unsynced;
    }
    if (payload.isEmpty) return true;
    try {
      final response = await http.post(Uri.parse('$_apiUrl/sync/push'), headers: {"Content-Type": "application/json"}, body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        for (String table in payload.keys) {
          await db.update(table, {'is_synced': 1}, where: 'is_synced = ?', whereArgs: [0]);
        }
        return true;
      }
      return false;
    } catch (e) { return false; }
  }

  Future<void> fetchAllFromServer(int magasinId) async {
    Database db = await database;
    String lastSync = await AuthService.getLastSyncDate(); 
    try {
      final response = await http.get(Uri.parse('$_apiUrl/sync/pull?since=$lastSync&magasin_id=$magasinId')).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        Map<String, dynamic> remoteData = jsonDecode(response.body);
        await db.transaction((txn) async {
          for (String table in remoteData.keys) {
            List<dynamic> rows = remoteData[table];
            for (var row in rows) {
              await txn.insert(table, {...row, 'is_synced': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        });
        await AuthService.setLastSyncDate(DateTime.now().toIso8601String());
      }
    } catch (e) { debugPrint("Erreur PULL: $e"); }
  }

  // --- DEPOTS ---
  Future<int> addDepot(String nom, int magasinId) async {
    Database db = await database;
    return await db.insert('depots', {'nomDepot': nom, 'magasin_id': magasinId, 'is_synced': 0});
  }

  Future<List<Map<String, dynamic>>> getDepots(int magasinId) async {
    Database db = await database;
    return await db.query('depots', where: 'magasin_id = ?', whereArgs: [magasinId], orderBy: 'nomDepot ASC');
  }

  // --- UTILISATEURS ---

  Future<int> register({
    required String nom,
    required String mdp,
    required String niveau,
    required String nomMagasin // C'est ici que l'on reçoit le nom de la boutique/dépôt
  }) async {
    Database db = await database;
    return await db.transaction((txn) async {
      int magasinId;

      if (niveau == 'boss') {
        // 1. Création du magasin avec le nom de l'entreprise (nomMagasin)
        // Note: La contrainte UNIQUE sur nomMagasin empêche deux boutiques d'avoir le même nom
        magasinId = await txn.insert('magasins', {
          'nomMagasin': nomMagasin,
          'is_synced': 0
        });



      } else {
        // Logique pour le vendeur : il cherche le magasin par son nom
        List<Map<String, dynamic>> resMag = await txn.query(
            'magasins',
            where: 'nomMagasin = ?',
            whereArgs: [nomMagasin]
        );

        if (resMag.isEmpty) {
          throw Exception("La boutique '$nomMagasin' n'existe pas. Vérifiez la boutique saisie par votre boss.");
        }
        magasinId = resMag.first['idMagasin'] as int;
      }

      // 3. Création de l'utilisateur lié au magasin
      // 'nom' est le login de l'utilisateur, 'nomMagasin' est le nom de son entité
      return await txn.insert('utilisateurs', {
        'nomUser': nom,
        'motDePasse': mdp,
        'niveauUser': niveau,
        'UserState': (niveau == 'boss') ? 1 : 0,
        'magasin_id': magasinId,
        'is_synced': 0,
      });
    });
  }


  Future<Map<String, dynamic>?> login(String nom, String mdp) async {
    Database db = await database;
    List<Map<String, dynamic>> res = await db.query('utilisateurs', where: 'nomUser = ? AND motDePasse = ?', whereArgs: [nom, mdp]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getUtilisateurs(int magasinId) async {
    Database db = await database;
    return await db.rawQuery('SELECT u.*, d.nomDepot FROM utilisateurs u LEFT JOIN depots d ON u.depot_id = d.idDepot WHERE u.magasin_id = ?', [magasinId]);
  }

  Future<int> validerUtilisateur(int idUser) async {
    Database db = await database;
    return await db.update('utilisateurs', {'UserState': 1, 'is_synced': 0}, where: 'idUser = ?', whereArgs: [idUser]);
  }

  Future<int> changerDepotUtilisateur(int idUser, int newDepotId) async {
    Database db = await database;
    return await db.update('utilisateurs', {'depot_id': newDepotId, 'is_synced': 0}, where: 'idUser = ?', whereArgs: [idUser]);
  }

  Future<int> supprimerUtilisateur(int idUser) async {
    Database db = await database;
    return await db.delete('utilisateurs', where: 'idUser = ?', whereArgs: [idUser]);
  }

  // --- STOCK ---
  Future<List<Map<String, dynamic>>> getProduits(int? depotId, {int? magasinId}) async {
    Database db = await database;
    if (depotId != null) {
      return await db.rawQuery('SELECT p.*, d.nomDepot FROM produits p JOIN depots d ON p.depot_id = d.idDepot WHERE p.depot_id = ? ORDER BY p.nom ASC', [depotId]);
    } else if (magasinId != null) {
      return await db.rawQuery('SELECT p.*, d.nomDepot FROM produits p JOIN depots d ON p.depot_id = d.idDepot WHERE d.magasin_id = ? ORDER BY p.nom ASC', [magasinId]);
    }
    return [];
  }

  Future<int> insertProduit(Map<String, dynamic> row, int depotId) async {
    Database db = await database;
    String nom = row['nom'].toString().trim();
    int qte = int.tryParse(row['quantite'].toString()) ?? 0;
    double prix = double.tryParse(row['prix_unitaire'].toString()) ?? 0.0;
    List<Map<String, dynamic>> existants = await db.query('produits', where: 'nom = ? AND depot_id = ?', whereArgs: [nom, depotId]);
    if (existants.isNotEmpty) {
      int idExistant = existants.first['id'] as int;
      await db.update('produits', {'prix_unitaire': prix, 'is_synced': 0}, where: 'id = ?', whereArgs: [idExistant]);
      return await reaprovisionner(idExistant, qte, depotId);
    } else {
      int id = await db.insert('produits', {'nom': nom, 'quantite': qte, 'prix_unitaire': prix, 'depot_id': depotId, 'is_synced': 0});
      await db.insert('mouvements', {'produit_id': id, 'nom_produit': nom, 'quantite': qte, 'type': 'ENTREE', 'date_mouvement': DateTime.now().toIso8601String(), 'depot_id': depotId, 'is_synced': 0});
      return id;
    }
  }

  Future<int> reaprovisionner(int id, int qte, int depotId) async {
    Database db = await database;
    var prod = await db.query('produits', where: 'id = ? AND depot_id = ?', whereArgs: [id, depotId]);
    if (prod.isEmpty) return 0;
    String nom = prod.first['nom'] as String;
    await db.insert('mouvements', {'produit_id': id, 'nom_produit': nom, 'quantite': qte, 'type': 'REAPPRO', 'date_mouvement': DateTime.now().toIso8601String(), 'depot_id': depotId, 'is_synced': 0});
    return await db.rawUpdate('UPDATE produits SET quantite = quantite + ?, is_synced = 0 WHERE id = ? AND depot_id = ?', [qte, id, depotId]);
  }

  Future<int> deleteProduit(int id) async {
    Database db = await database;
    return await db.delete('produits', where: 'id = ?', whereArgs: [id]);
  }

  // --- STATS ET VENTES ---
  Future<Map<String, double>> getStatistiques(int? depotId, {int? magasinId}) async {
    final db = await database;
    String filter;
    List<dynamic> args = [];
    if (depotId != null) { filter = "depot_id = ?"; args.add(depotId); }
    else if (magasinId != null) { filter = "depot_id IN (SELECT idDepot FROM depots WHERE magasin_id = ?)"; args.add(magasinId); }
    else return {'stock': 0, 'recette_jour': 0, 'recette_mois': 0};
    var stockRes = await db.rawQuery("SELECT SUM(quantite * prix_unitaire) as total FROM produits WHERE $filter", args);
    double stock = (stockRes.first['total'] as num?)?.toDouble() ?? 0.0;
    var jourRes = await db.rawQuery("SELECT SUM(prix_total) as total FROM ventes WHERE $filter AND date(date_vente) = date('now', 'localtime')", args);
    double recetteJour = (jourRes.first['total'] as num?)?.toDouble() ?? 0.0;
    var moisRes = await db.rawQuery("SELECT SUM(prix_total) as total FROM ventes WHERE $filter AND strftime('%Y-%m', date_vente) = strftime('%Y-%m', 'now', 'localtime')", args);
    double recetteMois = (moisRes.first['total'] as num?)?.toDouble() ?? 0.0;
    return {'stock': stock, 'recette_jour': recetteJour, 'recette_mois': recetteMois};
  }

  Future<bool> validerPanier(List<CartItem> items, String nomClient, int? depotId) async {
    Database db = await database;
    String idTransaction = DateTime.now().millisecondsSinceEpoch.toString();
    String dateVente = DateTime.now().toIso8601String();
    try {
      await db.transaction((txn) async {
        for (var item in items) {
          int effectiveDepotId = item.article.depotId ?? depotId!;
          List<Map> res = await txn.query('produits', where: 'id = ? AND depot_id = ?', whereArgs: [item.article.id, effectiveDepotId]);
          if (res.isEmpty) throw Exception("Produit non trouvé");
          int stockActuel = res.first['quantite'];
          if (stockActuel < item.quantity) throw Exception("Stock insuffisant");
          await txn.update('produits', {'quantite': stockActuel - item.quantity, 'is_synced': 0}, where: 'id = ? AND depot_id = ?', whereArgs: [item.article.id, effectiveDepotId]);
          await txn.insert('ventes', {'id_transaction': idTransaction, 'produit_id': item.article.id, 'nom_produit': item.article.nom, 'nom_client': nomClient, 'quantite_vendue': item.quantity, 'prix_total': item.article.prix * item.quantity, 'date_vente': dateVente, 'depot_id': effectiveDepotId, 'is_synced': 0});
        }
      });
      return true;
    } catch (e) { return false; }
  }

  Future<List<Map<String, dynamic>>> getVentesParDate(String datePrefix, int? depotId, {int? magasinId}) async {
    Database db = await database;
    if (depotId != null) {
      return await db.rawQuery('SELECT v.*, d.nomDepot FROM ventes v JOIN depots d ON v.depot_id = d.idDepot WHERE v.depot_id = ? AND v.date_vente LIKE ? ORDER BY v.date_vente DESC', [depotId, '$datePrefix%']);
    } else if (magasinId != null) {
      return await db.rawQuery('''SELECT v.*, d.nomDepot FROM ventes v JOIN depots d ON v.depot_id = d.idDepot WHERE d.magasin_id = ? AND v.date_vente LIKE ? ORDER BY v.date_vente DESC''', [magasinId, '$datePrefix%']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getRapportGlobal(int? depotId, {int? magasinId}) async {
    Database db = await database;
    String filter;
    List<dynamic> args = [];
    if (depotId != null) { filter = "depot_id = ?"; args = [depotId, depotId]; }
    else if (magasinId != null) { filter = "depot_id IN (SELECT idDepot FROM depots WHERE magasin_id = ?)"; args = [magasinId, magasinId]; }
    else return [];
    return await db.rawQuery('''SELECT v.nom_produit, v.quantite_vendue as quantite, 'VENTE' as type, v.date_vente as date, d.nomDepot FROM ventes v JOIN depots d ON v.depot_id = d.idDepot WHERE v.$filter UNION ALL SELECT m.nom_produit, m.quantite, m.type, m.date_mouvement as date, d.nomDepot FROM mouvements m JOIN depots d ON m.depot_id = d.idDepot WHERE m.$filter ORDER BY date DESC''', args);
  }

  static Future<void> sauvegarderBaseVersGmail() async {
    try {
      var databasesPath = await getDatabasesPath();
      String path = join(databasesPath, 'MaGestion.db');
      if (await File(path).exists()) { await Share.shareXFiles([XFile(path)], subject: 'Sauvegarde Boutique'); }
    } catch (e) { debugPrint("Erreur export : $e"); }
  }
}
