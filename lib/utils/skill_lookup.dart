import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../shared/rules_service.dart';

Future<Map<String, String>?> getSkillDetailsFromRules(String name, String type) async {
  final cachedJson = await RulesService.loadCachedRules();
  if (cachedJson == null) return null;

  final rules = json.decode(cachedJson);

  // ✅ Check Common skills (as a list)
  if (type == 'Common') {
    final commonList = rules['Common Skills'] as List<dynamic>? ?? [];
    final skill = commonList
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['Name'] == name, orElse: () => {});
    if (skill.isNotEmpty) {
      return {
        'verbal': '', // Common skills do not have verbals
        'rules': skill['Description'] ?? 'No description provided.',
      };
    }
  }

  // ✅ Determine if it's a race skill
  final races = rules['Races'] as List<dynamic>? ?? [];
  if (races.contains(type)) {
    final raceSkills = rules['Race Skills'] as List<dynamic>? ?? [];
    final skill = raceSkills
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['Race'] == type && s['Name'] == name, orElse: () => {});
    if (skill.isNotEmpty) {
      return {
        'verbal': skill['Verbal'] ?? 'No verbal provided.',
        'rules': skill['Rules'] ?? 'No rules provided.',
      };
    }
  }

  // ✅ Determine if it's an affinity skill
  final affinities = rules['Affinities'] as List<dynamic>? ?? [];
  if (affinities.contains(type)) {
    final affinitySkills = rules['Affinity Skills'] as List<dynamic>? ?? [];
    final skill = affinitySkills
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['Affinity'] == type && s['Name'] == name, orElse: () => {});
    if (skill.isNotEmpty) {
      return {
        'verbal': skill['Verbal'] ?? 'No verbal provided.',
        'rules': skill['Rules'] ?? 'No rules provided.',
      };
    }
  }

  return null;
}
