class Character {
  final String playerName;
  final String characterName;
  final int characterNumber;
  final String race;
  final int buildTotal;
  final int hitPoints;
  final bool cultivationTier;
  final List<Skill> skills;
  final Map<String, List<Affinity>> tiers;

  Character({
    required this.playerName,
    required this.characterName,
    required this.characterNumber,
    required this.race,
    required this.buildTotal,
    required this.hitPoints,
    required this.cultivationTier,
    required this.skills,
    required this.tiers,
  });

  factory Character.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> tiersRaw = json['tiers'];
    Map<String, List<Affinity>> parsedTiers = {};

    tiersRaw.forEach((tierName, tierData) {
      if (tierData != null && tierData['affinities'] != null) {
        parsedTiers[tierName] = List<Affinity>.from(
          tierData['affinities'].map((aff) => Affinity.fromJson(aff)),
        );
      }
    });

    return Character(
      playerName: json['playerName'],
      characterName: json['characterName'],
      characterNumber: json['characterNumber'],
      race: json['race'],
      buildTotal: json['buildTotal'],
      hitPoints: json['hitPoints'],
      cultivationTier: json['cultivationTier'] ?? false,
      skills: (json['skills'] as List<dynamic>)
          .map((skill) => Skill.fromJson(skill))
          .toList(),
      tiers: parsedTiers,
    );
  }
}

class Skill {
  final String name;
  final String type;
  final int level;
  final String frequency;

  Skill({
    required this.name,
    required this.type,
    required this.level,
    required this.frequency,
  });

  factory Skill.fromJson(Map<String, dynamic> json) {
    return Skill(
      name: json['name'],
      type: json['type'],
      level: json['level'],
      frequency: json['frequency'],
    );
  }
}

class Affinity {
  final String name;
  final int level;
  final dynamic affinityPointCost; // sometimes blank, sometimes a number

  Affinity({
    required this.name,
    required this.level,
    required this.affinityPointCost,
  });

  factory Affinity.fromJson(Map<String, dynamic> json) {
    return Affinity(
      name: json['name'],
      level: json['level'],
      affinityPointCost: json['affinityPointCost'],
    );
  }
}
