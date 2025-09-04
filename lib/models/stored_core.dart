class StoredCore {
  final String id;
  final String coreId;
  final int tier;
  final int uniqueNumber;
  final OriginalCoreData originalCoreData;
  final DateTime? storedAt;
  final String storedBy;
  final DateTime? tradedAt;
  final String? tradedFrom;
  final String? tradedTo;
  final String? tradedFromPlayer;
  final String? tradedToPlayer;

  StoredCore({
    required this.id,
    required this.coreId,
    required this.tier,
    required this.uniqueNumber,
    required this.originalCoreData,
    this.storedAt,
    required this.storedBy,
    this.tradedAt,
    this.tradedFrom,
    this.tradedTo,
    this.tradedFromPlayer,
    this.tradedToPlayer,
  });

  factory StoredCore.fromFirestore(Map<String, dynamic> data, String id) {
    return StoredCore(
      id: id,
      coreId: data['coreId'] ?? '',
      tier: data['tier'] ?? 1,
      uniqueNumber: data['uniqueNumber'] ?? 0,
      originalCoreData: OriginalCoreData.fromMap(data['originalCoreData'] ?? {}),
      storedAt: data['storedAt'] != null ? DateTime.parse(data['storedAt']) : null,
      storedBy: data['storedBy'] ?? '',
      tradedAt: data['tradedAt'] != null ? DateTime.parse(data['tradedAt']) : null,
      tradedFrom: data['tradedFrom'],
      tradedTo: data['tradedTo'],
      tradedFromPlayer: data['tradedFromPlayer'],
      tradedToPlayer: data['tradedToPlayer'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'coreId': coreId,
      'tier': tier,
      'uniqueNumber': uniqueNumber,
      'originalCoreData': originalCoreData.toMap(),
      'storedAt': storedAt?.toIso8601String(),
      'storedBy': storedBy,
      'tradedAt': tradedAt?.toIso8601String(),
      'tradedFrom': tradedFrom,
      'tradedTo': tradedTo,
      'tradedFromPlayer': tradedFromPlayer,
      'tradedToPlayer': tradedToPlayer,
    };
  }

  String get tierName {
    switch (tier) {
      case 1:
        return 'Iron';
      case 2:
        return 'Silver';
      case 3:
        return 'Gold';
      case 4:
        return 'Jade';
      case 5:
        return 'Saint';
      case 6:
        return 'Sovereign';
      default:
        return 'Unknown';
    }
  }

  bool get wasTraded => tradedAt != null;
}

class OriginalCoreData {
  final String game;
  final int timestamp;
  final String verificationHash;
  final String label;

  OriginalCoreData({
    required this.game,
    required this.timestamp,
    required this.verificationHash,
    required this.label,
  });

  factory OriginalCoreData.fromMap(Map<String, dynamic> data) {
    return OriginalCoreData(
      game: data['game'] ?? 'Crucible',
      timestamp: data['timestamp'] ?? 0,
      verificationHash: data['verificationHash'] ?? '',
      label: data['label'] ?? 'Monster Core',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'game': game,
      'timestamp': timestamp,
      'verificationHash': verificationHash,
      'label': label,
    };
  }
}
