class Event {
  final String startDate;
  final String endDate;
  final String type;
  final String location;

  Event({
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.location,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '',
      type: json['type'] ?? '',
      location: json['location'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startDate': startDate,
      'endDate': endDate,
      'type': type,
      'location': location,
    };
  }

  DateTime get startDateTime => DateTime.parse(startDate);
  DateTime get endDateTime => DateTime.parse(endDate);
  
  String get formattedStartDate {
    final date = startDateTime;
    return '${date.month}/${date.day}/${date.year}';
  }
  
  String get formattedEndDate {
    final date = endDateTime;
    return '${date.month}/${date.day}/${date.year}';
  }
  
  String get dateRange {
    if (startDate == endDate) {
      return formattedStartDate;
    }
    return '$formattedStartDate - $formattedEndDate';
  }
}

class EventsData {
  final List<Event> events;
  final String generatedAt;
  final String version;

  EventsData({
    required this.events,
    required this.generatedAt,
    required this.version,
  });

  factory EventsData.fromJson(Map<String, dynamic> json) {
    return EventsData(
      events: (json['events'] as List?)
          ?.map((eventJson) => Event.fromJson(eventJson))
          .toList() ?? [],
      generatedAt: json['generatedAt'] ?? '',
      version: json['version'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'events': events.map((event) => event.toJson()).toList(),
      'generatedAt': generatedAt,
      'version': version,
    };
  }
} 