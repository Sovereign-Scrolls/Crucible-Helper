import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RulesService {
  static const _boxName = 'rulesCache';
  static const _rulesKey = 'rules_json';
  static const _lastUpdatedKey = 'last_updated';

  /// Builds and caches the rules JSON from Firestore 'Rules' collections
  static Future<void> fetchAndCacheRules() async {
    // 1) Check remote Last Updated
    final rules = FirebaseFirestore.instance.collection('Rules');
    final lastUpdatedSnap = await rules.doc('Last Updated').get();
    final remoteStamp = (lastUpdatedSnap.data()?['date'] ?? '').toString();

    // 2) Ensure Hive initialized and box opened
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    final cachedStamp = (box.get(_lastUpdatedKey) ?? '').toString();

    // If unchanged and we already have cached rules, skip unless cache looks incomplete
    final hasCachedRules = box.containsKey(_rulesKey);
    if (hasCachedRules && cachedStamp == remoteStamp && remoteStamp.isNotEmpty) {
      final cachedJsonStr = box.get(_rulesKey) as String?;
      bool cacheLooksComplete = false;
      try {
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          final decoded = jsonDecode(cachedJsonStr);
          if (decoded is Map<String, dynamic>) {
            final races = (decoded['Races'] as List?) ?? const [];
            final hasRaceNames = races.isNotEmpty &&
                races.whereType<Map<String, dynamic>>().any((r) => (r['Name'] ?? '').toString().isNotEmpty);
            final commonSkills = (decoded['Common Skills'] as List?) ?? const [];
            final affinitySkills = (decoded['Affinity Skills'] as List?) ?? const [];
            // Consider complete if we have at least some names and some skills present
            cacheLooksComplete = hasRaceNames && (commonSkills.isNotEmpty || affinitySkills.isNotEmpty);
          }
        }
      } catch (_) {
        cacheLooksComplete = false;
      }
      if (cacheLooksComplete) return;
    }

    // 3) Load base collections
    final skillsDoc = rules.doc('Skills');

    final commonSnap = await skillsDoc.collection('Common').get();
    final raceSkillsSnap = await skillsDoc.collection('Races').get();

    // Affinities list (to discover per-affinity subcollections)
    final affinitiesSnap = await rules.doc('Affinities').collection('All').get();
    final affinityNames = affinitiesSnap.docs.map((d) => (d.id).toString()).toList();

    // 4) Read affinity skill subcollections
    final List<Map<String, dynamic>> affinitySkills = [];
    for (final affinityName in affinityNames) {
      try {
        final subSnap = await skillsDoc.collection(affinityName).get();
        for (final doc in subSnap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['Affinity'] ??= affinityName;
          affinitySkills.add(data);
        }
      } catch (_) {
        // Ignore missing collection for an affinity
      }
    }

    // 5) Read races and augment with race skills by race
    final racesAllSnap = await rules.doc('Races').collection('All').get();
    // Group race skills by 'Race' field
    final Map<String, List<Map<String, dynamic>>> raceToSkills = {};
    for (final s in raceSkillsSnap.docs) {
      final data = Map<String, dynamic>.from(s.data());
      final raceName = (data['Race'] ?? data['race'] ?? '').toString();
      if (raceName.isEmpty) continue;
      raceToSkills.putIfAbsent(raceName, () => <Map<String, dynamic>>[]).add(data);
    }

    final List<Map<String, dynamic>> racesJson = [];
    for (final r in racesAllSnap.docs) {
      final data = Map<String, dynamic>.from(r.data());
      final name = (data['Name'] ?? data['Race'] ?? r.id).toString();
      if (!data.containsKey('Name') || (data['Name']?.toString().isEmpty ?? true)) {
        data['Name'] = name;
      }
      // Normalize possible alternate description field keys
      if ((data['Description'] ?? '').toString().isEmpty) {
        final alt = (data['Desc'] ?? data['description'] ?? '').toString();
        if (alt.isNotEmpty) data['Description'] = alt;
      }
      if ((data['Costume Requirements'] ?? '').toString().isEmpty) {
        final alt = (data['Costume'] ?? data['CostumeRequirements'] ?? '').toString();
        if (alt.isNotEmpty) data['Costume Requirements'] = alt;
      }
      data['Race Skills'] = raceToSkills[name] ?? <Map<String, dynamic>>[];
      racesJson.add(data);
    }

    // 6) Status Effects
    final statusEffectsSnap = await rules.doc('Status Effects').collection('All').get();

    // 7) Build consolidated JSON compatible with the Rules UI
    final rulesJson = {
      'Common Skills': commonSnap.docs.map((d) => d.data()).toList(),
      'Race Skills': raceSkillsSnap.docs.map((d) => d.data()).toList(),
      'Affinity Skills': affinitySkills,
      'Races': racesJson,
      'Status Effects': statusEffectsSnap.docs.map((d) => d.data()).toList(),
      'Last Updated': { 'date': remoteStamp },
    };

    // 8) Persist to Hive
    await box.put(_rulesKey, jsonEncode(rulesJson));
    await box.put(_lastUpdatedKey, remoteStamp);
  }

  /// Loads the cached rules JSON from local storage
  static Future<String?> loadCachedRules() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    return box.get(_rulesKey) as String?;
  }

  /// Clear rules cache (e.g., on logout)
  static Future<void> clearCache() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    await box.delete(_rulesKey);
    await box.delete(_lastUpdatedKey);
    print('🗑️ Rules cache cleared');
  }
}