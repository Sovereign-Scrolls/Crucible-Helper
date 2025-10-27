import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CharacterCacheService {
  static const String _boxName = 'characterCache';

  // Key format: "{uid}_{characterNumber}". Fallback key when number unknown: "{uid}_primary"
  static String _makeKey(String uid, String characterNumber) => '${uid}_$characterNumber';

  static Future<Box> _openBox() async {
    return await Hive.openBox(_boxName);
  }

  // Convert Firestore-specific objects into JSON-encodable values for caching
  static dynamic _sanitizeForJson(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is DocumentReference) return value.path;
    if (value is GeoPoint) return {'lat': value.latitude, 'lng': value.longitude};
    if (value is Map) {
      final Map<String, dynamic> out = {};
      value.forEach((k, v) {
        out[k.toString()] = _sanitizeForJson(v);
      });
      return out;
    }
    if (value is List) {
      return value.map(_sanitizeForJson).toList();
    }
    return value;
  }

  /// Resolve the player's primary character document reference
  static Future<DocumentReference<Map<String, dynamic>>?> _resolveCharacterRef(FirebaseFirestore db, String uid) async {
    // Look for character in the player's characters collection
    print('🔍 CharacterCacheService: Looking for characters for user $uid');
    final query = await db.collection('players').doc(uid).collection('characters').limit(1).get();
    
    print('🔍 CharacterCacheService: Found ${query.docs.length} characters');
    if (query.docs.isEmpty) {
      print('❌ CharacterCacheService: No characters found for user $uid');
      return null;
    }
    
    final characterRef = query.docs.first.reference;
    print('✅ CharacterCacheService: Found character at ${characterRef.path}');
    return characterRef;
  }

  /// Pull a complete snapshot of character-derived data from Firestore
  static Future<Map<String, dynamic>?> fetchCharacterSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final db = FirebaseFirestore.instance;
    final charRef = await _resolveCharacterRef(db, user.uid);
    if (charRef == null) return null;

    final charSnap = await charRef.get();
    if (!charSnap.exists) return null;

    // Load subcollections we render on the New Sheet
    final futures = <Future>[];
    Map<String, dynamic> result = {
      'character': charSnap.data(),
    };

    // essence/summary
    futures.add(charRef.collection('essence').doc('summary').get().then((s) {
      result['essence'] = s.data();
    }));

    // build (all + Total)
    futures.add(charRef.collection('build').get().then((s) {
      final entries = <Map<String, dynamic>>[];
      Map<String, dynamic>? total;
      for (final d in s.docs) {
        if (d.id.toLowerCase() == 'total') {
          total = d.data();
        } else {
          entries.add({'id': d.id, ...d.data()});
        }
      }
      result['build'] = {'entries': entries, 'total': total};
    }));

    // affinity_points (all + Total)
    futures.add(charRef.collection('affinity_points').get().then((s) {
      final entries = <Map<String, dynamic>>[];
      Map<String, dynamic>? total;
      for (final d in s.docs) {
        if (d.id.toLowerCase() == 'total') {
          total = d.data();
        } else {
          entries.add({'id': d.id, ...d.data()});
        }
      }
      result['affinity_points'] = {'entries': entries, 'total': total};
    }));

    // ascend/current
    futures.add(charRef.collection('ascend').doc('current').get().then((s) {
      result['ascend'] = s.data();
    }));

    // affinities (tiers)
    futures.add(charRef.collection('affinities').get().then((aff) async {
      final affMap = <String, dynamic>{};
      for (final a in aff.docs) {
        final tiers = await a.reference.collection('tiers').get();
        final tierMap = <String, dynamic>{};
        for (final t in tiers.docs) {
          tierMap[t.id] = t.data();
        }
        affMap[a.id] = tierMap;
      }
      result['affinities'] = affMap;
    }));

    // skills/Total cost only (optional)
    futures.add(charRef.collection('skills').doc('Total').get().then((s) {
      result['skillsTotal'] = s.data();
    }));
    futures.add(charRef.collection('skills').get().then((typesSnap) async {
      final entries = <Map<String, dynamic>>[];
      final List<Future> enrichFutures = [];
      for (final typeDoc in typesSnap.docs) {
        final typeId = typeDoc.id;
        if (typeId.toLowerCase() == 'total') continue;
        try {
          final itemsSnap = await typeDoc.reference.collection('items').get();
          for (final item in itemsSnap.docs) {
            final data = Map<String, dynamic>.from(item.data());
            data['name'] ??= item.id;
            data['type'] ??= typeId;
            // Normalize level to lowercase key alongside existing Level
            final dynamic rawLevel = data['level'] ?? data['Level'];
            if (rawLevel is num) data['level'] = rawLevel.toInt();
            if (rawLevel is String) data['level'] = int.tryParse(rawLevel) ?? 0;
            // Enrich from Rules with fallbacks (typeId -> Common -> Races) and sanitized ids
            enrichFutures.add(() async {
              final rulesSkills = FirebaseFirestore.instance.collection('Rules').doc('Skills');
              String rawId = item.id;
              String sanitized = rawId.replaceAll('/', ' - ').replaceAll(RegExp(r"\s+"), ' ').trim();
              final candidates = <String>[rawId];
              if (sanitized != rawId) candidates.add(sanitized);
              final collections = <String>[typeId, 'Common', 'Races'];
              Map<String, dynamic>? r;
              for (final col in collections) {
                for (final id in candidates) {
                  try {
                    final snap = await rulesSkills.collection(col).doc(id).get();
                    if (snap.exists) { r = snap.data(); }
                  } catch (_) {}
                  if (r != null) break;
                }
                if (r != null) break;
              }
              if (r != null) {
                data['Frequency'] = r['Frequency'] ?? data['Frequency'];
                data['frequency'] = (r['Frequency'] ?? data['frequency'])?.toString();
                if (r['Delivery'] != null) data['delivery'] = r['Delivery'];
                if (r['Verbal'] != null) data['verbal'] = r['Verbal'];
                if (r['Description'] != null) data['description'] = r['Description'];
              }
            }());
            entries.add(data);
          }
        } catch (_) {
          // If no items subcollection, fall back to using the type doc as one entry
          final data = Map<String, dynamic>.from(typeDoc.data());
          data['name'] ??= typeId;
          data['type'] ??= typeId;
          final dynamic rawLevel = data['level'] ?? data['Level'];
          if (rawLevel is num) data['level'] = rawLevel.toInt();
          if (rawLevel is String) data['level'] = int.tryParse(rawLevel) ?? 0;
          entries.add(data);
        }
      }
      await Future.wait(enrichFutures);
      result['skillsEntries'] = entries;
    }));

    await Future.wait(futures);

    // Attach timestamps
    result['cachedAt'] = DateTime.now().toIso8601String();
    result['characterRefPath'] = charRef.path;

    return result;
  }

  static Future<void> cacheSnapshot(Map<String, dynamic> snapshot) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final box = await _openBox();
    // Prefer character.characterNumber if available, else mark as primary
    final character = (snapshot['character'] ?? {}) as Map<String, dynamic>;
    final characterNumber = (character['characterNumber'] ?? 'primary').toString();
    final key = _makeKey(user.uid, characterNumber);
    final sanitized = _sanitizeForJson(snapshot) as Map<String, dynamic>;
    await box.put(key, json.encode(sanitized));
    await box.put('${key}_lastSyncedAt', sanitized['cachedAt']);
  }

  static Future<Map<String, dynamic>?> loadCachedSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final db = await _openBox();
    // Try by iterating keys that start with uid_
    final prefix = '${user.uid}_';
    for (final k in db.keys) {
      if (k is String && k.startsWith(prefix) && !k.endsWith('_lastSyncedAt')) {
        final raw = db.get(k);
        if (raw is String) {
          try { return json.decode(raw) as Map<String, dynamic>; } catch (_) {}
        }
      }
    }
    return null;
  }

  /// If advancement/last_sync.updatedAt is newer than cachedAt (or no cache), refresh cache
  static Future<bool> refreshIfStale() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final db = FirebaseFirestore.instance;
    final charRef = await _resolveCharacterRef(db, user.uid);
    if (charRef == null) return false;
    final lastSyncSnap = await charRef.collection('advancement').doc('last_sync').get();
    final lastSync = lastSyncSnap.data()?['updatedAt'];

    DateTime? lastSyncTime;
    if (lastSync is Timestamp) lastSyncTime = lastSync.toDate();
    if (lastSync is String) lastSyncTime = DateTime.tryParse(lastSync);

    final cached = await loadCachedSnapshot();
    DateTime? cachedAt;
    if (cached != null) {
      cachedAt = DateTime.tryParse(cached['cachedAt'] ?? '');
    }

    final needsRefresh = lastSyncTime == null || cachedAt == null || lastSyncTime.isAfter(cachedAt);
    if (!needsRefresh) return false;

    final fresh = await fetchCharacterSnapshot();
    if (fresh == null) return false;
    await cacheSnapshot(fresh);
    return true;
  }

  /// Clear character cache (e.g., on logout)
  static Future<void> clearCache() async {
    try {
      final box = await _openBox();
      await box.clear();
      print('🗑️ Character cache cleared');
    } catch (e) {
      print('Error clearing character cache: $e');
    }
  }
}


