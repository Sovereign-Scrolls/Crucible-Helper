import 'dart:convert';
import '../shared/rules_service.dart';

Future<Map<String, String>?> getSkillDetailsFromRules(String name, String type, String characterRace) async {
  final cachedJson = await RulesService.loadCachedRules();
  if (cachedJson == null) return null;

  final rules = json.decode(cachedJson);

  // Search Common Skills
  if (type == 'Common') {
    final skills = rules['Common Skills'] as List<dynamic>? ?? [];
    final skill = skills.firstWhere(
      (s) => s['Name'] == name,
      orElse: () => null,
    );
    if (skill != null) {
      return {
        'verbal': skill['Verbal'] ?? '',
        'rules': skill['Description'] ?? 'No rules provided.',
      };
    }
  }

  // Search Race Skills
  final races = rules['Races'] as List<dynamic>? ?? [];
  print('Looking for characterRace: $characterRace');
  print('Available races: ${races.map((r) => r['Name']).join(', ')}');

  final race = races.firstWhere(
    (r) => r['Name'] == characterRace,
    orElse: () {
      print('❌ Race "$characterRace" not found.');
      return null;
    },
  );

  if (race != null && race['Race Skills'] != null) {
    final skills = race['Race Skills'] as List<dynamic>;
    print('Looking for skill: $name in race: ${race['Name']}');
    final skill = skills.firstWhere(
      (s) => s['Name'] == name,
      orElse: () {
        print('❌ Skill "$name" not found in ${race['Name']} Race Skills.');
        return null;
      },
    );
    if (skill != null) {
      return {
        'verbal': '',
        'rules': skill['Description'] ?? 'No description.',
      };
    }
  }

  // Search Affinity Skills
  final affinitySkills = rules['Affinity Skills'] as List<dynamic>? ?? [];
  final affinitySkill = affinitySkills.firstWhere(
    (s) => s['Name'] == name && s['Affinity'] == type,
    orElse: () => null,
  );
  if (affinitySkill != null) {
    return {
      'verbal': affinitySkill['Verbal'] ?? '',
      'rules': affinitySkill['Description'] ?? 'No rules provided.',
    };
  }

  return null;
}
