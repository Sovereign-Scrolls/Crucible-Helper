class MonsterCore {
  final String id;
  final String game;
  final int timestamp;
  final String verificationHash;
  final String label;
  final int tier;
  final int uniqueNumber;
  final bool isActive;

  MonsterCore({
    required this.id,
    required this.game,
    required this.timestamp,
    required this.verificationHash,
    required this.label,
    required this.tier,
    required this.uniqueNumber,
    required this.isActive,
  });

  factory MonsterCore.fromFirestore(Map<String, dynamic> data, String id) {
    return MonsterCore(
      id: id,
      game: data['game'] ?? 'Crucible',
      timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      verificationHash: data['verificationHash'] ?? '',
      label: data['label'] ?? 'Monster Core',
      tier: data['tier'] ?? 1,
      uniqueNumber: data['uniqueNumber'] ?? 0,
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'game': game,
      'timestamp': timestamp,
      'verificationHash': verificationHash,
      'label': label,
      'tier': tier,
      'uniqueNumber': uniqueNumber,
      'isActive': isActive,
    };
  }

  Map<String, dynamic> toQRData() {
    return {
      'game': game,
      'timestamp': timestamp,
      'verificationHash': verificationHash,
      'label': label,
      'tier': tier,
      'uniqueNumber': uniqueNumber,
      'isActive': isActive,
    };
  }
}
