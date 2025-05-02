class Character {
  final String playerName;
  final String characterName;
  final int characterNumber;
  final String race;
  final Build build;
  final Map<String, dynamic> affinityPoints;
  final Map<String, dynamic> hitPoints; 
  final String cultivationTier;
  final List<Skill> skills;
  final Map<String, AffinityDetail> affinities;

  Character({
    required this.playerName,
    required this.characterName,
    required this.characterNumber,
    required this.race,
    required this.build,
    required this.affinityPoints,
    required this.hitPoints,
    required this.cultivationTier,
    required this.skills,
    required this.affinities,
  });

  factory Character.fromJson(Map<String, dynamic> json) {

    return Character(
      playerName: json['playerName'],
      characterName: json['characterName'],
      characterNumber: json['characterNumber'],
      race: json['race'],
      build: Build.fromJson(json['build']),
      affinityPoints: json['affinityPoints'] ?? {},
      hitPoints: json['hitPoints'],
      cultivationTier: json['cultivationTier'],
      skills: (json['skills'] as List<dynamic>)
          .map((skill) => Skill.fromJson(skill))
          .toList(),
      affinities: (json['affinities'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          AffinityDetail.fromJson(value as Map<String, dynamic>),
        ),
      ),
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

class AffinityDetail {
  final int effectLevel;
  final Map<String, int> tiers;

  AffinityDetail({required this.effectLevel, required this.tiers});

  factory AffinityDetail.fromJson(Map<String, dynamic> json) {
    final tiers = <String, int>{};

    for (final key in json.keys) {
      if (key != 'effectLevel') {
        tiers[key] = json[key];
      }
    }

    return AffinityDetail(
      effectLevel: json['effectLevel'],
      tiers: tiers,
    );
  }
}

class Build {
  final int total;
  final StartingBuild starting;
  final List<BuildGain> gains;

  Build({required this.total, required this.starting, required this.gains});

  factory Build.fromJson(Map<String, dynamic> json) {
    return Build(
      total: json['total'],
      starting: StartingBuild.fromJson(json['starting']),
      gains: (json['gains'] as List).map((e) => BuildGain.fromJson(e)).toList(),
    );
  }
}

class StartingBuild {
  final int amount;
  final String date;

  StartingBuild({required this.amount, required this.date});

  factory StartingBuild.fromJson(Map<String, dynamic> json) {
    return StartingBuild(
      amount: json['amount'],
      date: json['date'],
    );
  }
}

class BuildGain {
  final int amount;
  final String reason;
  final String note;
  final String date;

  BuildGain({
    required this.amount,
    required this.reason,
    required this.note,
    required this.date,
  });

  factory BuildGain.fromJson(Map<String, dynamic> json) {
    return BuildGain(
      amount: json['amount'],
      reason: json['reason'],
      note: json['note'],
      date: json['date'],
    );
  }
}