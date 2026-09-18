import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../models/CartItem.dart';
import '../utilis/auth_service.dart';
import '../utilis/remote_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Chaque enregistrement possède son UUID local.
  String _generateLocalUuid() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(bytes).replaceAll('=', '');
    return '$timestamp-$suffix';
  }

  // Avec une clé composite (id, Local_uuid), l'id est généré manuellement.
  Future<int> _nextId(
    DatabaseExecutor db,
    String table,
    String idColumn,
  ) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX($idColumn), 0) + 1 AS next_id FROM $table',
    );
    return (result.first['next_id'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> getDepots(int magasinId) async {
    final db = await database;
    return db.query('depots', where: 'magasin_id = ?', whereArgs: [magasinId]);
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'MaGestion.db');

    return openDatabase(
      path,
      version: 21,
      onCreate: (db, version) => _onCreate(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 21) {
          final expectedTables = [
            'magasins',
            'depots',
            'produits',
            'utilisateurs',
            'ventes',
            'mouvements',
          ];
          final existingTables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (${List.filled(expectedTables.length, '?').join(',')})",
            expectedTables,
          );
          if (existingTables.length != expectedTables.length) {
            await _recreateSchema(db, expectedTables);
          } else {
            await _migrateToLocalUuid(db);
          }
        }
      },
    );
  }

  Future<void> _recreateSchema(Database db, List<String> tableNames) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.transaction((txn) async {
      for (final table in tableNames.reversed) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }
      await _onCreate(txn);
    });
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // Migration des anciennes tables vers la structure avec Local_uuid.
  Future<void> _migrateToLocalUuid(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');

    await db.transaction((txn) async {
      final tables = [
        'magasins',
        'depots',
        'produits',
        'ventes',
        'mouvements',
        'utilisateurs',
      ];

      final oldData = <String, List<Map<String, dynamic>>>{};

      for (final table in tables) {
        oldData[table] = await txn.query(table);
      }

      for (final table in tables.reversed) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }

      await _onCreate(txn);

      final magasinUuid = <int, String>{};
      final depotUuid = <int, String>{};
      final produitUuid = <int, String>{};

      for (final row in oldData['magasins'] ?? []) {
        final id = row['idMagasin'] as int;
        final uuid = (row['Local_uuid'] as String?) ?? _generateLocalUuid();
        magasinUuid[id] = uuid;

        await txn.insert('magasins', {
          'idMagasin': id,
          'Local_uuid': uuid,
          'nomMagasin': row['nomMagasin'],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }

      for (final row in oldData['depots'] ?? []) {
        final id = row['idDepot'] as int;
        final magasinId = row['magasin_id'] as int;
        final uuid = (row['Local_uuid'] as String?) ?? _generateLocalUuid();
        depotUuid[id] = uuid;

        await txn.insert('depots', {
          'idDepot': id,
          'Local_uuid': uuid,
          'nomDepot': row['nomDepot'],
          'magasin_id': magasinId,
          'magasin_uuid': magasinUuid[magasinId],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }

      for (final row in oldData['produits'] ?? []) {
        final id = row['id'] as int;
        final depotId = row['depot_id'] as int?;
        final uuid = (row['Local_uuid'] as String?) ?? _generateLocalUuid();
        produitUuid[id] = uuid;

        await txn.insert('produits', {
          'id': id,
          'Local_uuid': uuid,
          'nom': row['nom'],
          'quantite': row['quantite'] ?? 0,
          'prix_unitaire': row['prix_unitaire'] ?? 0.0,
          'depot_id': depotId,
          'depot_uuid': depotId == null ? null : depotUuid[depotId],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }

      for (final row in oldData['ventes'] ?? []) {
        final produitId = row['produit_id'] as int?;
        final depotId = row['depot_id'] as int?;

        await txn.insert('ventes', {
          'id': row['id'] as int,
          'Local_uuid': (row['Local_uuid'] as String?) ?? _generateLocalUuid(),
          'id_transaction': row['id_transaction'],
          'produit_id': produitId,
          'produit_uuid': produitId == null ? null : produitUuid[produitId],
          'nom_produit': row['nom_produit'],
          'nom_client': row['nom_client'],
          'quantite_vendue': row['quantite_vendue'],
          'prix_total': row['prix_total'],
          'date_vente': row['date_vente'],
          'depot_id': depotId,
          'depot_uuid': depotId == null ? null : depotUuid[depotId],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }

      for (final row in oldData['mouvements'] ?? []) {
        final produitId = row['produit_id'] as int?;
        final depotId = row['depot_id'] as int?;

        await txn.insert('mouvements', {
          'id': row['id'] as int,
          'Local_uuid': (row['Local_uuid'] as String?) ?? _generateLocalUuid(),
          'produit_id': produitId,
          'produit_uuid': produitId == null ? null : produitUuid[produitId],
          'nom_produit': row['nom_produit'],
          'quantite': row['quantite'],
          'type': row['type'],
          'date_mouvement': row['date_mouvement'],
          'depot_id': depotId,
          'depot_uuid': depotId == null ? null : depotUuid[depotId],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }

      for (final row in oldData['utilisateurs'] ?? []) {
        final magasinId = row['magasin_id'] as int;
        final depotId = row['depot_id'] as int?;

        await txn.insert('utilisateurs', {
          'idUser': row['idUser'],
          'Local_uuid': (row['Local_uuid'] as String?) ?? _generateLocalUuid(),
          'nomUser': row['nomUser'],
          'motDePasse': row['motDePasse'],
          'niveauUser': row['niveauUser'],
          'UserState': row['UserState'] ?? 0,
          'magasin_id': magasinId,
          'magasin_uuid': magasinUuid[magasinId],
          'depot_id': depotId,
          'depot_uuid': depotId == null ? null : depotUuid[depotId],
          'is_synced': row['is_synced'] ?? 0,
          'LastUpdated': row['LastUpdated'],
          'IsDeleted': row['IsDeleted'] ?? 0,
        });
      }
    });

    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE magasins (
        idMagasin INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        nomMagasin TEXT NOT NULL UNIQUE,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (idMagasin, Local_uuid)
      )
    ''');

    await db.execute('''
      CREATE TABLE depots (
        idDepot INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        nomDepot TEXT NOT NULL,
        magasin_id INTEGER NOT NULL,
        magasin_uuid TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (idDepot, Local_uuid),
        FOREIGN KEY (magasin_id, magasin_uuid)
          REFERENCES magasins (idMagasin, Local_uuid)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE produits (
        id INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        nom TEXT NOT NULL COLLATE NOCASE,
        quantite INTEGER DEFAULT 0,
        prix_unitaire REAL DEFAULT 0.0,
        depot_id INTEGER,
        depot_uuid TEXT,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, Local_uuid),
        FOREIGN KEY (depot_id, depot_uuid)
          REFERENCES depots (idDepot, Local_uuid)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ventes (
        id INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        id_transaction TEXT,
        produit_id INTEGER,
        produit_uuid TEXT,
        nom_produit TEXT,
        nom_client TEXT,
        quantite_vendue INTEGER,
        prix_total REAL,
        date_vente TEXT,
        depot_id INTEGER,
        depot_uuid TEXT,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, Local_uuid),
        FOREIGN KEY (produit_id, produit_uuid)
          REFERENCES produits (id, Local_uuid)
          ON DELETE SET NULL,
        FOREIGN KEY (depot_id, depot_uuid)
          REFERENCES depots (idDepot, Local_uuid)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE mouvements (
        id INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        produit_id INTEGER,
        produit_uuid TEXT,
        nom_produit TEXT,
        quantite INTEGER,
        type TEXT,
        date_mouvement TEXT,
        depot_id INTEGER,
        depot_uuid TEXT,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, Local_uuid),
        FOREIGN KEY (produit_id, produit_uuid)
          REFERENCES produits (id, Local_uuid)
          ON DELETE SET NULL,
        FOREIGN KEY (depot_id, depot_uuid)
          REFERENCES depots (idDepot, Local_uuid)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE utilisateurs (
        idUser INTEGER NOT NULL,
        Local_uuid TEXT NOT NULL,
        nomUser TEXT NOT NULL UNIQUE COLLATE NOCASE,
        motDePasse TEXT NOT NULL,
        niveauUser TEXT NOT NULL,
        UserState INTEGER DEFAULT 0,
        magasin_id INTEGER NOT NULL,
        magasin_uuid TEXT NOT NULL,
        depot_id INTEGER,
        depot_uuid TEXT,
        is_synced INTEGER DEFAULT 0,
        LastUpdated TEXT DEFAULT NULL,
        IsDeleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (idUser, Local_uuid),
        FOREIGN KEY (magasin_id, magasin_uuid)
          REFERENCES magasins (idMagasin, Local_uuid)
          ON DELETE CASCADE,
        FOREIGN KEY (depot_id, depot_uuid)
          REFERENCES depots (idDepot, Local_uuid)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_magasin_depots ON depots (magasin_id, magasin_uuid)',
    );
    await db.execute(
      'CREATE INDEX idx_magasin_users ON utilisateurs (magasin_id, magasin_uuid)',
    );
    await db.execute(
      'CREATE INDEX idx_prod_depot ON produits (depot_id, depot_uuid)',
    );
  }

  Future<int> getUnsyncedCount() async {
    final unsyncedChanges = await getUnsyncedChanges();
    return unsyncedChanges.values.fold<int>(
      0,
      (total, rows) => total + rows.length,
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> getUnsyncedChanges() async {
    final db = await database;
    final tables = [
      'magasins',
      'depots',
      'produits',
      'utilisateurs',
      'ventes',
      'mouvements',
    ];
    final changes = <String, List<Map<String, dynamic>>>{};

    for (final table in tables) {
      final rows = await db.query(
        table,
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      if (rows.isNotEmpty) changes[table] = rows;
    }

    return changes;
  }

  Future<void> markChangesAsSynced(
    Map<String, List<Map<String, dynamic>>> changes,
  ) async {
    final db = await database;
    const idColumns = {
      'magasins': 'idMagasin',
      'depots': 'idDepot',
      'produits': 'id',
      'utilisateurs': 'idUser',
      'ventes': 'id',
      'mouvements': 'id',
    };

    await db.transaction((txn) async {
      for (final entry in changes.entries) {
        final idColumn = idColumns[entry.key];

        for (final row in entry.value) {
          final localUuid = row['Local_uuid'];
          if (localUuid == null) continue;

          final updatedRows = await txn.update(
            entry.key,
            {'is_synced': 1},
            where: 'Local_uuid = ? AND is_synced = 0',
            whereArgs: [localUuid],
          );

          if (updatedRows == 0 && idColumn != null && row[idColumn] != null) {
            await txn.update(
              entry.key,
              {'is_synced': 1},
              where: '$idColumn = ? AND is_synced = 0',
              whereArgs: [row[idColumn]],
            );
          }
        }
      }
    });
  }

  Future<bool> syncAllLocalToServer() async {
    final tables = [
      'magasins',
      'depots',
      'produits',
      'utilisateurs',
      'ventes',
      'mouvements',
    ];

    final db = await database;
    final payload = <String, List<Map<String, dynamic>>>{};

    for (final table in tables) {
      final unsynced = await db.query(
        table,
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      if (unsynced.isNotEmpty) payload[table] = unsynced;
    }

    if (payload.isEmpty) return true;

    final success = await RemoteService().syncToCloud(payload);

    if (success) {
      for (final table in payload.keys) {
        await db.update(
          table,
          {'is_synced': 1},
          where: 'is_synced = ?',
          whereArgs: [0],
        );
      }
      return true;
    }

    return false;
  }

  Future<void> fetchAllFromServer(int magasinId) async {
    final db = await database;
    final lastSync = await AuthService.getLastSyncDate();
    final remoteData = await RemoteService().fetchFromCloud(
      magasinId,
      lastSync,
    );

    if (remoteData != null) {
      await db.transaction((txn) async {
        for (final table in remoteData.keys) {
          final rows = remoteData[table] as List<dynamic>;

          for (final row in rows) {
            final data = Map<String, dynamic>.from(row as Map);
            data['Local_uuid'] ??= _generateLocalUuid();
            data['is_synced'] = 1;

            await txn.insert(
              table,
              data,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      await AuthService.setLastSyncDate(DateTime.now().toIso8601String());
    }
  }

  // ---------------------------------------------------------------------------
  // MAGASINS / DEPOTS
  // ---------------------------------------------------------------------------

  Future<int> addMagasin(String nom) async {
    final db = await database;

    return db.transaction((txn) async {
      final magId = await _nextId(txn, 'magasins', 'idMagasin');
      final magasinUuid = _generateLocalUuid();

      await txn.insert('magasins', {
        'idMagasin': magId,
        'Local_uuid': magasinUuid,
        'nomMagasin': nom,
        'is_synced': 0,
      });

      final depotId = await _nextId(txn, 'depots', 'idDepot');

      await txn.insert('depots', {
        'idDepot': depotId,
        'Local_uuid': _generateLocalUuid(),
        'nomDepot': nom,
        'magasin_id': magId,
        'magasin_uuid': magasinUuid,
        'is_synced': 0,
      });

      return magId;
    });
  }

  Future<int> addDepot(String nom, int magasinId) async {
    final db = await database;

    final magasin = await db.query(
      'magasins',
      columns: ['idMagasin', 'Local_uuid'],
      where: 'idMagasin = ?',
      whereArgs: [magasinId],
      limit: 1,
    );

    if (magasin.isEmpty) throw Exception('Magasin introuvable');

    final depotId = await _nextId(db, 'depots', 'idDepot');

    return db.insert('depots', {
      'idDepot': depotId,
      'Local_uuid': _generateLocalUuid(),
      'nomDepot': nom,
      'magasin_id': magasinId,
      'magasin_uuid': magasin.first['Local_uuid'],
      'is_synced': 0,
    });
  }

  // ---------------------------------------------------------------------------
  // UTILISATEURS
  // ---------------------------------------------------------------------------

  Future<int> register({
    required String nom,
    required String mdp,
    required String niveau,
    required String nomMagasin,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      late int magasinId;
      late String magasinUuid;

      final resMag = await txn.query(
        'magasins',
        where: 'nomMagasin = ?',
        whereArgs: [nomMagasin],
      );

      if (resMag.isNotEmpty) {
        magasinId = resMag.first['idMagasin'] as int;
        magasinUuid = resMag.first['Local_uuid'] as String;
      } else {
        magasinId = await _nextId(txn, 'magasins', 'idMagasin');
        magasinUuid = _generateLocalUuid();

        await txn.insert('magasins', {
          'idMagasin': magasinId,
          'Local_uuid': magasinUuid,
          'nomMagasin': nomMagasin,
          'is_synced': 0,
        });

        final depotId = await _nextId(txn, 'depots', 'idDepot');

        await txn.insert('depots', {
          'idDepot': depotId,
          'Local_uuid': _generateLocalUuid(),
          'nomDepot': nomMagasin,
          'magasin_id': magasinId,
          'magasin_uuid': magasinUuid,
          'is_synced': 0,
        });
      }

      final userId = await _nextId(txn, 'utilisateurs', 'idUser');

      return txn.insert('utilisateurs', {
        'idUser': userId,
        'Local_uuid': _generateLocalUuid(),
        'nomUser': nom,
        'motDePasse': mdp,
        'niveauUser': niveau,
        'UserState': niveau == 'boss' ? 1 : 0,
        'magasin_id': magasinId,
        'magasin_uuid': magasinUuid,
        'is_synced': 0,
      });
    });
  }

  Future<Map<String, dynamic>?> login(String nom, String mdp) async {
    final db = await database;
    final res = await db.query(
      'utilisateurs',
      where: 'nomUser = ? AND motDePasse = ?',
      whereArgs: [nom, mdp],
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getUtilisateurs(int magasinId) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT u.*, d.nomDepot
      FROM utilisateurs u
      LEFT JOIN depots d
        ON u.depot_id = d.idDepot
       AND u.depot_uuid = d.Local_uuid
      WHERE u.magasin_id = ?
    ''',
      [magasinId],
    );
  }

  Future<int> validerUtilisateur(int idUser) async {
    final db = await database;
    return db.update(
      'utilisateurs',
      {'UserState': 1, 'is_synced': 0},
      where: 'idUser = ?',
      whereArgs: [idUser],
    );
  }

  Future<int> changerDepotUtilisateur(int idUser, int newDepotId) async {
    final db = await database;

    final depot = await db.query(
      'depots',
      columns: ['idDepot', 'Local_uuid'],
      where: 'idDepot = ?',
      whereArgs: [newDepotId],
      limit: 1,
    );

    if (depot.isEmpty) throw Exception('Dépôt introuvable');

    return db.update(
      'utilisateurs',
      {
        'depot_id': newDepotId,
        'depot_uuid': depot.first['Local_uuid'],
        'is_synced': 0,
      },
      where: 'idUser = ?',
      whereArgs: [idUser],
    );
  }

  Future<int> supprimerUtilisateur(int idUser) async {
    final db = await database;
    return db.delete('utilisateurs', where: 'idUser = ?', whereArgs: [idUser]);
  }

  // ---------------------------------------------------------------------------
  // PRODUITS / STOCK
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getProduits(
    int? depotId, {
    int? magasinId,
  }) async {
    final db = await database;

    if (depotId != null) {
      return db.rawQuery(
        '''
        SELECT p.*, d.nomDepot
        FROM produits p
        JOIN depots d
          ON p.depot_id = d.idDepot
         AND p.depot_uuid = d.Local_uuid
        WHERE p.depot_id = ?
        ORDER BY p.nom ASC
      ''',
        [depotId],
      );
    }

    if (magasinId != null) {
      return db.rawQuery(
        '''
        SELECT p.*, d.nomDepot
        FROM produits p
        JOIN depots d
          ON p.depot_id = d.idDepot
         AND p.depot_uuid = d.Local_uuid
        WHERE d.magasin_id = ?
        ORDER BY p.nom ASC
      ''',
        [magasinId],
      );
    }

    return [];
  }

  Future<int> insertProduit(Map<String, dynamic> row, int depotId) async {
    final db = await database;

    final nom = row['nom'].toString().trim();
    final qte = int.tryParse(row['quantite'].toString()) ?? 0;
    final prix = double.tryParse(row['prix_unitaire'].toString()) ?? 0.0;

    final depot = await db.query(
      'depots',
      columns: ['idDepot', 'Local_uuid'],
      where: 'idDepot = ?',
      whereArgs: [depotId],
      limit: 1,
    );

    if (depot.isEmpty) throw Exception('Dépôt introuvable');

    final depotUuid = depot.first['Local_uuid'] as String;

    final existants = await db.query(
      'produits',
      where: 'nom = ? AND depot_id = ? AND depot_uuid = ?',
      whereArgs: [nom, depotId, depotUuid],
    );

    if (existants.isNotEmpty) {
      final idExistant = existants.first['id'] as int;
      final produitUuid = existants.first['Local_uuid'] as String;

      await db.update(
        'produits',
        {'prix_unitaire': prix, 'is_synced': 0},
        where: 'id = ? AND Local_uuid = ?',
        whereArgs: [idExistant, produitUuid],
      );

      return reaprovisionner(idExistant, qte, depotId);
    }

    final id = await _nextId(db, 'produits', 'id');
    final localUuid = _generateLocalUuid();

    await db.insert('produits', {
      'id': id,
      'Local_uuid': localUuid,
      'nom': nom,
      'quantite': qte,
      'prix_unitaire': prix,
      'depot_id': depotId,
      'depot_uuid': depotUuid,
      'is_synced': 0,
    });

    final mouvementId = await _nextId(db, 'mouvements', 'id');

    await db.insert('mouvements', {
      'id': mouvementId,
      'Local_uuid': _generateLocalUuid(),
      'produit_id': id,
      'produit_uuid': localUuid,
      'nom_produit': nom,
      'quantite': qte,
      'type': 'ENTREE',
      'date_mouvement': DateTime.now().toIso8601String(),
      'depot_id': depotId,
      'depot_uuid': depotUuid,
      'is_synced': 0,
    });

    return id;
  }

  Future<int> reaprovisionner(int id, int qte, int depotId) async {
    final db = await database;

    final prod = await db.query(
      'produits',
      where: 'id = ? AND depot_id = ?',
      whereArgs: [id, depotId],
    );

    if (prod.isEmpty) return 0;

    final nom = prod.first['nom'] as String;
    final produitUuid = prod.first['Local_uuid'] as String;
    final depotUuid = prod.first['depot_uuid'] as String;

    final mouvementId = await _nextId(db, 'mouvements', 'id');

    await db.insert('mouvements', {
      'id': mouvementId,
      'Local_uuid': _generateLocalUuid(),
      'produit_id': id,
      'produit_uuid': produitUuid,
      'nom_produit': nom,
      'quantite': qte,
      'type': 'REAPPRO',
      'date_mouvement': DateTime.now().toIso8601String(),
      'depot_id': depotId,
      'depot_uuid': depotUuid,
      'is_synced': 0,
    });

    return db.rawUpdate(
      '''
      UPDATE produits
      SET quantite = quantite + ?, is_synced = 0
      WHERE id = ? AND Local_uuid = ? AND depot_id = ?
      ''',
      [qte, id, produitUuid, depotId],
    );
  }

  Future<int> deleteProduit(int id) async {
    final db = await database;
    return db.delete('produits', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // STATISTIQUES / VENTES
  // ---------------------------------------------------------------------------

  Future<Map<String, double>> getStatistiques(
    int? depotId, {
    int? magasinId,
  }) async {
    final db = await database;

    String filter;
    List<dynamic> args = [];

    if (depotId != null) {
      filter = 'depot_id = ?';
      args.add(depotId);
    } else if (magasinId != null) {
      filter = 'depot_id IN (SELECT idDepot FROM depots WHERE magasin_id = ?)';
      args.add(magasinId);
    } else {
      return {'stock': 0, 'recette_jour': 0, 'recette_mois': 0};
    }

    final stockRes = await db.rawQuery(
      'SELECT SUM(quantite * prix_unitaire) as total '
      'FROM produits WHERE $filter',
      args,
    );

    final stock = (stockRes.first['total'] as num?)?.toDouble() ?? 0.0;

    final jourRes = await db.rawQuery(
      "SELECT SUM(prix_total) as total FROM ventes WHERE $filter "
      "AND date(date_vente) = date('now', 'localtime')",
      args,
    );

    final recetteJour = (jourRes.first['total'] as num?)?.toDouble() ?? 0.0;

    final moisRes = await db.rawQuery(
      "SELECT SUM(prix_total) as total FROM ventes WHERE $filter "
      "AND strftime('%Y-%m', date_vente) = "
      "strftime('%Y-%m', 'now', 'localtime')",
      args,
    );

    final recetteMois = (moisRes.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'stock': stock,
      'recette_jour': recetteJour,
      'recette_mois': recetteMois,
    };
  }

  Future<bool> validerPanier(
    List<CartItem> items,
    String nomClient,
    int? depotId,
  ) async {
    final db = await database;
    final idTransaction = DateTime.now().millisecondsSinceEpoch.toString();
    final dateVente = DateTime.now().toIso8601String();

    try {
      await db.transaction((txn) async {
        for (final item in items) {
          final effectiveDepotId = item.article.depotId ?? depotId!;

          final res = await txn.query(
            'produits',
            where: 'id = ? AND depot_id = ?',
            whereArgs: [item.article.id, effectiveDepotId],
          );

          if (res.isEmpty) throw Exception('Produit non trouvé');

          final stockActuel = res.first['quantite'] as int;
          final produitUuid = res.first['Local_uuid'] as String;
          final depotUuid = res.first['depot_uuid'] as String;

          if (stockActuel < item.quantity) {
            throw Exception('Stock insuffisant');
          }

          await txn.update(
            'produits',
            {'quantite': stockActuel - item.quantity, 'is_synced': 0},
            where: 'id = ? AND Local_uuid = ?',
            whereArgs: [item.article.id, produitUuid],
          );

          final venteId = await _nextId(txn, 'ventes', 'id');

          await txn.insert('ventes', {
            'id': venteId,
            'Local_uuid': _generateLocalUuid(),
            'id_transaction': idTransaction,
            'produit_id': item.article.id,
            'produit_uuid': produitUuid,
            'nom_produit': item.article.nom,
            'nom_client': nomClient,
            'quantite_vendue': item.quantity,
            'prix_total': item.article.prix * item.quantity,
            'date_vente': dateVente,
            'depot_id': effectiveDepotId,
            'depot_uuid': depotUuid,
            'is_synced': 0,
          });
        }
      });

      return true;
    } catch (e) {
      debugPrint('Erreur validation panier: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getVentesParDate(
    String datePrefix,
    int? depotId, {
    int? magasinId,
  }) async {
    final db = await database;

    if (depotId != null) {
      return db.rawQuery(
        '''
        SELECT v.*, d.nomDepot
        FROM ventes v
        JOIN depots d
          ON v.depot_id = d.idDepot
         AND v.depot_uuid = d.Local_uuid
        WHERE v.depot_id = ?
          AND v.date_vente LIKE ?
        ORDER BY v.date_vente DESC
      ''',
        [depotId, '$datePrefix%'],
      );
    }

    if (magasinId != null) {
      return db.rawQuery(
        '''
        SELECT v.*, d.nomDepot
        FROM ventes v
        JOIN depots d
          ON v.depot_id = d.idDepot
         AND v.depot_uuid = d.Local_uuid
        WHERE d.magasin_id = ?
          AND v.date_vente LIKE ?
        ORDER BY v.date_vente DESC
      ''',
        [magasinId, '$datePrefix%'],
      );
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> getRapportGlobal({
    int? depotId,
    int? magasinId,
  }) async {
    final db = await database;

    String filter;
    List<dynamic> args = [];

    if (depotId != null) {
      filter = 'depot_id = ?';
      args = [depotId, depotId];
    } else if (magasinId != null) {
      filter = 'depot_id IN (SELECT idDepot FROM depots WHERE magasin_id = ?)';
      args = [magasinId, magasinId];
    } else {
      return [];
    }

    return db.rawQuery('''
      SELECT
        v.nom_produit,
        v.quantite_vendue AS quantite,
        'VENTE' AS type,
        v.date_vente AS date,
        d.nomDepot
      FROM ventes v
      JOIN depots d
        ON v.depot_id = d.idDepot
       AND v.depot_uuid = d.Local_uuid
      WHERE v.$filter

      UNION ALL

      SELECT
        m.nom_produit,
        m.quantite,
        m.type,
        m.date_mouvement AS date,
        d.nomDepot
      FROM mouvements m
      JOIN depots d
        ON m.depot_id = d.idDepot
       AND m.depot_uuid = d.Local_uuid
      WHERE m.$filter

      ORDER BY date DESC
    ''', args);
  }

  // ---------------------------------------------------------------------------
  // BACKUP
  // ---------------------------------------------------------------------------

  static Future<void> sauvegarderBaseVersGmail() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'MaGestion.db');

      if (await File(path).exists()) {
        await Share.shareXFiles([XFile(path)], subject: 'Sauvegarde Boutique');
      }
    } catch (e) {
      debugPrint('Erreur export : $e');
    }
  }
}
