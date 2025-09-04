# Unsubmitted Advancement JSON Structure

This document describes the JSON structure for unsubmitted advancement data that will be sent to a Google App Script.

## Overview

The JSON represents all pending character advancement changes that haven't been submitted yet. It includes three types of changes:
- **Affinity Changes**: Changes to character affinities (e.g., Attack, Defense)
- **Skill Changes**: Changes to skills (both existing and new skills)
- **Essence Changes**: Changes to essence (Direct Buy)

**Note**: The internal Flutter code uses additional fields like `adjustment` for processing, but these are excluded from the JSON submission to keep the API clean and focused.

## JSON Structure

```json
{
  "affinityChanges": [...],
  "skillChanges": [...],
  "essenceChanges": [...]
}
```

## Affinity Changes

Represents changes to character affinities.

### Fields:
- **timestamp** (string): ISO 8601 timestamp when the change was made
- **affinityName** (string): Name of the affinity (e.g., "Attack", "Defense", "Perception")
- **cost** (integer): Cost in Affinity Points (AP)
- **levelChange** (integer): Change in level (+1 for increase, -1 for decrease)

### Example:
```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "affinityName": "Attack",
  "cost": 15,
  "levelChange": 1
}
```

## Skill Changes

Represents changes to skills (both existing skills and new skills).

### Fields:
- **timestamp** (string): ISO 8601 timestamp when the change was made
- **skillName** (string): Name of the skill (e.g., "Fireball", "Healing Touch")
- **skillType** (string): Type of skill (e.g., "Combat", "Utility", "Affinity")
- **levelChange** (integer): Change in level (+1 for increase, -1 for decrease)
- **cost** (integer): Cost in Build Points

### Example:
```json
{
  "timestamp": "2024-01-15T10:40:00.000Z",
  "skillName": "Fireball",
  "skillType": "Combat",
  "levelChange": 1,
  "cost": 3
}
```

## Essence Changes

Represents changes to essence through Direct Buy.

### Fields:
- **timestamp** (string): ISO 8601 timestamp when the change was made
- **essenceAdjustment** (integer): Change in essence (+1 for increase, -1 for decrease)
- **cost** (integer): Cost in Build Points (2 per essence)

### Example:
```json
{
  "timestamp": "2024-01-15T10:50:00.000Z",
  "essenceAdjustment": 3,
  "cost": 6
}
```

## Complete Example

```json
{
  "affinityChanges": [
    {
      "timestamp": "2024-01-15T10:30:00.000Z",
      "affinityName": "Attack",
      "cost": 15,
      "levelChange": 1
    },
    {
      "timestamp": "2024-01-15T10:35:00.000Z",
      "affinityName": "Defense",
      "cost": 6,
      "levelChange": 1
    }
  ],
  "skillChanges": [
    {
      "timestamp": "2024-01-15T10:40:00.000Z",
      "skillName": "Fireball",
      "skillType": "Combat",
      "levelChange": 1,
      "cost": 3
    },
    {
      "timestamp": "2024-01-15T10:45:00.000Z",
      "skillName": "Healing Touch",
      "skillType": "Utility",
      "levelChange": 2,
      "cost": 5
    }
  ],
  "essenceChanges": [
    {
      "timestamp": "2024-01-15T10:50:00.000Z",
      "essenceAdjustment": 3,
      "cost": 6
    }
  ]
}
```

## Notes for Google App Script

1. **Timestamps**: All timestamps are in ISO 8601 format (UTC)
2. **Costs**: 
   - Affinity changes use Affinity Points (AP)
   - Skill and Essence changes use Build Points
3. **Level Changes**: Can be positive (increase) or negative (decrease)
4. **Empty Arrays**: If no changes of a type exist, the array will be empty `[]`
5. **Validation**: The Google App Script should validate:
   - All required fields are present
   - Cost values are positive
   - Timestamps are valid ISO 8601 format
   - Level changes are within acceptable ranges

## Processing Order

The Google App Script should process changes in this order:
1. **Essence Changes** (affects total HP)
2. **Affinity Changes** (affects affinity levels and costs)
3. **Skill Changes** (affects skill levels and costs)

This ensures that all dependent calculations are updated correctly.
