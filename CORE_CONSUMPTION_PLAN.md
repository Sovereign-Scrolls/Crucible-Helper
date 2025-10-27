# Core Consumption Tracking Implementation Plan

## Overview
Implement event-based core consumption tracking that links to active events and tracks consumption during events.

## Database Schema Changes

### Character Document Structure
Add new fields to character documents:
```
/players/{uid}/characters/{characterNumber}/
  - activeEvent: string (event ID) or null
  - consumedCores: number (default: 0)
  - maxConsume: number (default: 0)
  
  /events/{eventId}/  (new subcollection)
    - eventId: string
    - eventName: string
    - startDate: timestamp
    - endDate: timestamp
    - attendingAs: string
    - consumedCores: number
    - maxConsume: number
    
    /advancement/{docId}/ (advancement entries during this event)
      - (all advancement fields)
```

## Implementation Steps

### 1. Check-In Function (`functions/index.js` - `checkIn`)
When a character is checked in:
- Set `activeEvent` = eventId
- Create `/events/{eventId}` subcollection entry with:
  - eventName (from events collection)
  - startDate (from events collection)
  - endDate (from events collection)
  - attendingAs (PC/NPC/Cleanup)
  - consumedCores: 0
  - maxConsume: (based on attendingAs and event settings)
- Set character root-level `consumedCores` = 0
- Set character root-level `maxConsume` = event's max consume value

### 2. CalculateCharacter Function (`functions/index.js` - `calculateCharacter`)
Modify to:
- Reset `consumedCores` to 0 at start
- Check if `activeEvent` exists
- If activeEvent exists:
  - Check if current date is within event startDate/endDate
  - If within dates:
    - For each advancement row:
      - Add to active event's advancement subcollection
      - If reason === "Consuming Cores":
        - Increment `consumedCores` by 1
- Update character's `consumedCores` field
- Calculate `canConsume` = maxConsume - consumedCores

### 3. Character Model Updates (`lib/models/character.dart`)
Add new fields:
```dart
class Character {
  //... existing fields
  final String? activeEvent;
  final int consumedCores;
  final int maxConsume;
  
  int get canConsume => maxConsume - consumedCores;
}
```

### 4. Flutter UI Updates (`lib/main.dart`)
Change "Can Consume" display:
```dart
// OLD:
Text('Coming soon')

// NEW:
Text('${widget.character.canConsume}')
```

## File Changes Required

1. **functions/index.js**
   - `checkIn` function (~line 7275)
   - `calculateCharacter` function (~line 3103)

2. **lib/models/character.dart**
   - Add activeEvent, consumedCores, maxConsume fields
   - Add canConsume getter
   - Update fromJson/toJson

3. **lib/main.dart**
   - Update "Can Consume" display (line 1279)

4. **App Script/uploadToFirebase.js**
   - Update `generateCharacterJsonFromLogs` to include new fields

## Questions/Considerations

1. **Max Consume Value Source**: Where do we get the max consume value for each attending type?
   - From events collection?
   - From a separate rules collection?
   - Hardcoded values?

2. **Event End Behavior**: When an event ends:
   - Should activeEvent be cleared automatically?
   - Should consumedCores persist or reset?
   - Should old event data be archived?

3. **Multiple Characters**: Can a player check in multiple characters to the same event?
   - Each character should have its own activeEvent and consumption tracking

4. **Advancement Reason Matching**: 
   - Exact match: "Consuming Cores"
   - Or variations: "Consume Core", "consuming core", etc.?
   - Need to normalize the comparison

5. **Historical Tracking**: 
   - Should we keep all past events in the events subcollection?
   - Or only the active one?

## Testing Checklist

- [ ] Check-in creates activeEvent and event subcollection
- [ ] Check-in sets consumedCores and maxConsume correctly
- [ ] CalculateCharacter resets consumedCores to 0
- [ ] CalculateCharacter adds advancement to event subcollection
- [ ] CalculateCharacter increments consumedCores for core consumption
- [ ] Flutter UI shows correct canConsume value
- [ ] Multiple characters can have different active events
- [ ] Event date range validation works correctly

## Implementation Order

1. ✅ Create this plan document
2. ⏳ Get answers to questions above
3. ⏳ Update Character model
4. ⏳ Update checkIn function
5. ⏳ Update calculateCharacter function
6. ⏳ Update Flutter UI
7. ⏳ Update Apps Script (if needed)
8. ⏳ Test complete flow
9. ⏳ Deploy

---

**Next Steps**: Please review this plan and provide answers to the questions in the "Questions/Considerations" section, then I'll proceed with implementation.

