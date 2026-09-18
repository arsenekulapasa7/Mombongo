class SyncModel {
  final String serverConnexionString;
  final String localDb;
  final String fileName;
  final DateTime? lastSyncDate;
  final Map<String, List<Map<String, dynamic>>> localChanges;

  SyncModel({
    required this.serverConnexionString,
    required this.localDb,
    required this.fileName,
    this.lastSyncDate,
    this.localChanges = const {},
  });

  factory SyncModel.fromJson(Map<String, dynamic> json) {
    final dateStr =
        json['LastSyncDate'] as String? ?? json['lastSyncDate'] as String?;
    final parsedDate = dateStr != null ? DateTime.tryParse(dateStr) : null;

    final Map<String, List<Map<String, dynamic>>> parsedLocalChanges = {};

    final rawLocalChanges = json['LocalChanges'] ?? json['localChanges'];
    if (rawLocalChanges is Map<String, dynamic>) {
      final rawMap = rawLocalChanges;

      rawMap.forEach((key, value) {
        if (value is List) {
          final itemsList = <Map<String, dynamic>>[];

          for (final item in value) {
            if (item is Map) {
              final safeMap = Map<String, dynamic>.from(item);
              itemsList.add(safeMap);
            }
          }

          parsedLocalChanges[key] = itemsList;
        }
      });
    }

    return SyncModel(
        serverConnexionString:
          json['ServerConnexionString'] as String? ??
          json['serverConnexionString'] as String? ??
          '',
      localDb: json['localDb'] as String? ?? 'MaGestion.db',
        fileName: json['ConfigFileName'] as String? ??
          json['configFileName'] as String? ??
          json['fileName'] as String? ??
          '',
      lastSyncDate: parsedDate,
      localChanges: parsedLocalChanges,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ConfigFileName': fileName,
      'ServerConnexionString': serverConnexionString,
      'LastSyncDate': lastSyncDate?.toIso8601String(),
      'LocalChanges': localChanges,
    };
  }
}
