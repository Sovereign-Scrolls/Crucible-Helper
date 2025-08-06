import 'package:flutter_test/flutter_test.dart';
import 'package:crucible_helper/models/character.dart';

void main() {
  group('Character Model Tests', () {
    test('Character fromJson should create valid object', () {
      final jsonData = {
        'playerName': 'Test Player',
        'characterName': 'Test Character',
        'characterNumber': 1,
        'race': 'Human',
        'build': {
          'total': 10,
          'unspent': 2,
          'needToAscend': 0,
          'starting': {
            'amount': 8,
            'date': '2024-01-01'
          },
          'gains': []
        },
        'affinityPoints': {
          'affinityPointsTotal': 10,
          'affinityTierPointUnspent': 5
        },
        'hitPoints': {
          'current': 100,
          'maximum': 100
        },
        'dr': {
          'physical': 5,
          'magical': 3
        },
        'cultivationTier': 'Novice',
        'skills': [],
        'affinities': {
          'fire': {
            'effectLevel': 1,
            'tier1': 2,
            'tier2': 1
          }
        }
      };

      final character = Character.fromJson(jsonData);

      expect(character.playerName, equals('Test Player'));
      expect(character.characterName, equals('Test Character'));
      expect(character.characterNumber, equals(1));
      expect(character.race, equals('Human'));
      expect(character.cultivationTier, equals('Novice'));
    });

    test('Character getters should work correctly', () {
      final jsonData = {
        'playerName': 'Test Player',
        'characterName': 'Test Character',
        'characterNumber': 1,
        'race': 'Human',
        'build': {
          'total': 15,
          'unspent': 3,
          'needToAscend': 0,
          'starting': {
            'amount': 12,
            'date': '2024-01-01'
          },
          'gains': []
        },
        'affinityPoints': {
          'affinityPointsTotal': 15,
          'affinityTierPointUnspent': 3
        },
        'hitPoints': {
          'current': 100,
          'maximum': 100
        },
        'dr': {
          'physical': 5,
          'magical': 3
        },
        'cultivationTier': 'Novice',
        'skills': [],
        'affinities': {
          'water': {
            'effectLevel': 2,
            'tier1': 3,
            'tier2': 2
          }
        }
      };

      final character = Character.fromJson(jsonData);

      expect(character.totalAffinityPoints, equals(15));
      expect(character.unspentAffinityPoints, equals(3));
    });
  });

  group('Skill Model Tests', () {
    test('Skill fromJson should create valid object', () {
      final jsonData = {
        'name': 'Fireball',
        'type': 'Combat',
        'level': 3,
        'frequency': 'At Will',
        'verbal': 'I cast Fireball',
        'description': 'A powerful fire spell',
        'delivery': 'Touch'
      };

      final skill = Skill.fromJson(jsonData);

      expect(skill.name, equals('Fireball'));
      expect(skill.type, equals('Combat'));
      expect(skill.level, equals(3));
      expect(skill.frequency, equals('At Will'));
      expect(skill.verbal, equals('I cast Fireball'));
      expect(skill.description, equals('A powerful fire spell'));
      expect(skill.delivery, equals('Touch'));
    });

    test('Skill toJson should return valid JSON', () {
      final skill = Skill(
        name: 'Fireball',
        type: 'Combat',
        level: 3,
        frequency: 'At Will',
        verbal: 'I cast Fireball',
        description: 'A powerful fire spell',
        delivery: 'Touch'
      );

      final json = skill.toJson();

      expect(json['name'], equals('Fireball'));
      expect(json['type'], equals('Combat'));
      expect(json['level'], equals(3));
      expect(json['frequency'], equals('At Will'));
      expect(json['verbal'], equals('I cast Fireball'));
      expect(json['description'], equals('A powerful fire spell'));
      expect(json['delivery'], equals('Touch'));
    });
  });

  group('Build Model Tests', () {
    test('Build fromJson should create valid object', () {
      final jsonData = {
        'total': 20,
        'unspent': 5,
        'needToAscend': 0,
        'starting': {
          'amount': 15,
          'date': '2024-01-01'
        },
        'gains': [
          {
            'amount': 3,
            'reason': 'Event reward',
            'note': 'Great roleplay',
            'date': '2024-02-01'
          }
        ]
      };

      final build = Build.fromJson(jsonData);

      expect(build.total, equals(20));
      expect(build.unspent, equals(5));
      expect(build.needToAscend, equals(0));
      expect(build.starting.amount, equals(15));
      expect(build.gains.length, equals(1));
      expect(build.gains.first.amount, equals(3));
      expect(build.gains.first.reason, equals('Event reward'));
    });
  });
} 