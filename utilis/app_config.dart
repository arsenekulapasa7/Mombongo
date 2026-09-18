class AppConfig {
  static const localDatabaseName = 'MaGestion.db';
  static const configurationFileName = 'config_tables.txt';

  static const configurationTables = <String>[
    'magasins',
    'depots',
    'produits',
    'utilisateurs',
    'ventes',
    'mouvements',
  ];

  static const apiBaseUrl = 'http://afrisofttech-002-site50.jtempurl.com';

  static const sqlConnectionString =
      'Data Source=SQL5083.site4now.net;'
      'Initial Catalog=db_a54efd_synchronizedb;'
      'User Id=db_a54efd_synchronizedb_admin;'
      'Password=12345678GL;'
      'Encrypt=True;TrustServerCertificate=True;';
}
