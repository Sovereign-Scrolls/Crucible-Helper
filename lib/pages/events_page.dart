import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';


class Event {
  final String id;
  final String startDate;
  final String endDate;
  final String locationName;
  final String locationAddress;
  final String typeName;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool registrationActivated;
  final Map<String, dynamic>? registrationDetails;

  Event({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.locationName,
    required this.locationAddress,
    required this.typeName,
    required this.startDateTime,
    required this.endDateTime,
    this.registrationActivated = false,
    this.registrationDetails,
  });

  String get dateRange => '$startDate - $endDate';
  String get location => locationName;
  String get type => typeName;

  factory Event.fromFirestore(Map<String, dynamic> data, String id) {
    return Event(
      id: id,
      startDate: data['startDate'] ?? '',
      endDate: data['endDate'] ?? '',
      locationName: data['locationName'] ?? '',
      locationAddress: data['locationAddress'] ?? '',
      typeName: data['typeName'] ?? '',
      startDateTime: DateTime.parse(data['startDate'] ?? DateTime.now().toIso8601String()),
      endDateTime: DateTime.parse(data['endDate'] ?? DateTime.now().toIso8601String()),
      registrationActivated: data['registrationActivated'] ?? false,
      registrationDetails: data['registrationDetails'],
    );
  }
}

class Location {
  final String id;
  final String name;
  final String address;
  final String timezone;

  Location({
    required this.id,
    required this.name,
    required this.address,
    required this.timezone,
  });

  factory Location.fromFirestore(Map<String, dynamic> data, String id) {
    return Location(
      id: id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      timezone: data['timezone'] ?? 'America/New_York',
    );
  }
}

class EventType {
  final String id;
  final String name;
  final double defaultCost;
  final double defaultPreregCost;
  final List<Map<String, dynamic>> npcShifts;
  final int numberOfNpcShifts;
  final int numberOfCleanupShifts;
  final List<String> cleanupShifts;
  final List<String> payOptions;

  EventType({
    required this.id,
    required this.name,
    this.defaultCost = 0,
    this.defaultPreregCost = 0,
    this.npcShifts = const [],
    this.numberOfNpcShifts = 0,
    this.numberOfCleanupShifts = 0,
    this.cleanupShifts = const [],
    this.payOptions = const [],
  });

  factory EventType.fromFirestore(Map<String, dynamic> data, String id) {
    return EventType(
      id: id,
      name: data['name'] ?? '',
      defaultCost: (data['defaultCost'] ?? 0).toDouble(),
      defaultPreregCost: (data['defaultPreregCost'] ?? 0).toDouble(),
      npcShifts: List<Map<String, dynamic>>.from(data['npcShifts'] ?? []),
      numberOfNpcShifts: data['numberOfNpcShifts'] ?? 0,
      numberOfCleanupShifts: data['numberOfCleanupShifts'] ?? 0,
      cleanupShifts: List<String>.from(data['cleanupShifts'] ?? []),
      payOptions: List<String>.from(data['payOptions'] ?? []),
    );
  }
}

class EventAttendeeType {
  final String id;
  final String name;
  final int buildForEvent;
  final int affinityPointsForEvent;
  final int maxConsumeForEvent;

  EventAttendeeType({
    required this.id,
    required this.name,
    this.buildForEvent = 0,
    this.affinityPointsForEvent = 0,
    this.maxConsumeForEvent = 0,
  });

  factory EventAttendeeType.fromFirestore(Map<String, dynamic> data, String id) {
    return EventAttendeeType(
      id: id,
      name: data['name'] ?? '',
      buildForEvent: data['buildForEvent'] ?? 0,
      affinityPointsForEvent: data['affinityPointsForEvent'] ?? 0,
      maxConsumeForEvent: data['maxConsumeForEvent'] ?? 0,
    );
  }
}

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  _EventsPageState createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Event> events = [];
  List<Location> locations = [];
  List<EventType> eventTypes = [];
  List<EventAttendeeType> attendeeTypes = [];
  bool isLoading = true;
  bool isSuperAdmin = false;
  bool isLoadingPermissions = true;
  bool isProcessingCheckIn = false;
  Map<String, bool> eventRegistrationStatus = {};
  Map<String, bool> isLoadingRegistrationStatus = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadEvents();
    _loadAttendeeTypes();
  }

  Future<void> _loadAttendeeTypes() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventAttendeeTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final attendeeTypesList = data['attendeeTypes'] as List;
          final loadedAttendeeTypes = attendeeTypesList.map((attendeeTypeData) {
            return EventAttendeeType.fromFirestore(attendeeTypeData, attendeeTypeData['id']);
          }).toList();

          setState(() {
            attendeeTypes = loadedAttendeeTypes;
          });
        }
      }
    } catch (error) {
      print('❌ Error loading attendee types: $error');
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          isSuperAdmin = false;
          isLoadingPermissions = false;
        });
        return;
      }

      print('🔍 Checking permissions for user: ${user.uid} (${user.email})');

      // Get ID token for Firebase Function call
      final idToken = await user.getIdToken();
      
      // Check if user is a super admin using Firebase Function
      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkSuperAdmin'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isAdmin = data['ok'] == true && data['isSuperAdmin'] == true;
        
        print('🔍 Super admin check result: $isAdmin');
        
        setState(() {
          isSuperAdmin = isAdmin;
          isLoadingPermissions = false;
        });

        if (isAdmin) {
          print('✅ User is super admin');
          _loadLocationsAndTypes();
        }
      } else {
        print('❌ Error checking super admin status: ${response.statusCode}');
        setState(() {
          isSuperAdmin = false;
          isLoadingPermissions = false;
        });
      }

    } catch (error) {
      print('❌ Error checking permissions: $error');
      setState(() {
        isSuperAdmin = false;
        isLoadingPermissions = false;
      });
    }
  }

  Future<void> checkEventRegistrationStatus(String eventId) async {
    try {
      setState(() {
        isLoadingRegistrationStatus[eventId] = true;
      });

      final user = _auth.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getUserEventRegistration?eventId=$eventId'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isRegistered = data['ok'] == true && data['registration'] != null;
        
        setState(() {
          eventRegistrationStatus[eventId] = isRegistered;
          isLoadingRegistrationStatus[eventId] = false;
        });
      } else {
        setState(() {
          eventRegistrationStatus[eventId] = false;
          isLoadingRegistrationStatus[eventId] = false;
        });
      }
    } catch (error) {
      print('Error checking registration status for event $eventId: $error');
      setState(() {
        eventRegistrationStatus[eventId] = false;
        isLoadingRegistrationStatus[eventId] = false;
      });
    }
  }

  Future<void> _loadEvents() async {
    try {
      setState(() {
        isLoading = true;
      });

      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Get ID token for Firebase Function call
      final idToken = await user.getIdToken();
      
      // Call Firebase Function to get events
      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEvents'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final eventsList = data['events'] as List;
          final loadedEvents = eventsList.map((eventData) {
            return Event.fromFirestore(eventData, eventData['id']);
          }).toList();

          setState(() {
            events = loadedEvents;
            isLoading = false;
          });
        } else {
          print('❌ Error loading events: ${data['error']}');
          setState(() {
            isLoading = false;
          });
        }
      } else {
        print('❌ HTTP error loading events: ${response.statusCode}');
        setState(() {
          isLoading = false;
        });
      }

    } catch (error) {
      print('❌ Error loading events: $error');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadLocationsAndTypes() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      // Load locations
      final locationsResponse = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getLocations'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (locationsResponse.statusCode == 200) {
        final locationsData = json.decode(locationsResponse.body);
        if (locationsData['ok'] == true) {
          final locationsList = locationsData['locations'] as List;
          final loadedLocations = locationsList.map((locationData) {
            return Location.fromFirestore(locationData, locationData['id']);
          }).toList();

          setState(() {
            locations = loadedLocations;
          });
        }
      }

      // Load event types
      final typesResponse = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (typesResponse.statusCode == 200) {
        final typesData = json.decode(typesResponse.body);
        if (typesData['ok'] == true) {
          final typesList = typesData['types'] as List;
          final loadedTypes = typesList.map((typeData) {
            return EventType.fromFirestore(typeData, typeData['id']);
          }).toList();

          setState(() {
            eventTypes = loadedTypes;
          });
        }
      }

      // Load attendee types
      final attendeeTypesResponse = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventAttendeeTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (attendeeTypesResponse.statusCode == 200) {
        final attendeeTypesData = json.decode(attendeeTypesResponse.body);
        if (attendeeTypesData['ok'] == true) {
          final attendeeTypesList = attendeeTypesData['attendeeTypes'] as List;
          final loadedAttendeeTypes = attendeeTypesList.map((attendeeTypeData) {
            return EventAttendeeType.fromFirestore(attendeeTypeData, attendeeTypeData['id']);
          }).toList();

          setState(() {
            attendeeTypes = loadedAttendeeTypes;
          });
        }
      }

    } catch (error) {
      print('❌ Error loading locations and types: $error');
    }
  }

  // Show event creation modal
  void _showCreateEventModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _CreateEventModal(
          locations: locations,
          eventTypes: eventTypes,
          onEventCreated: () {
            _loadEvents();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show location creation modal
  void _showCreateLocationModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _CreateLocationModal(
          onLocationCreated: () {
            _loadLocationsAndTypes();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show event type creation modal
  void _showCreateEventTypeModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _CreateEventTypeModal(
          onEventTypeCreated: () {
            _loadLocationsAndTypes();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show event type list modal for editing
  void _showEventTypeListModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _EventTypeListModal(
          eventTypes: eventTypes,
          onEventTypeUpdated: () {
            _loadLocationsAndTypes();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show location list modal for editing
  void _showLocationListModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _LocationListModal(
          locations: locations,
          onLocationUpdated: () {
            _loadLocationsAndTypes();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show activate registration modal
  void _showActivateRegistrationModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _ActivateRegistrationModal(
          event: event,
          eventTypes: eventTypes,
          onRegistrationActivated: () {
            _loadEvents();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show edit registration modal
  void _showEditRegistrationModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _EditRegistrationModal(
          event: event,
          onRegistrationUpdated: () {
            _loadEvents();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show register for event modal
  void _showRegisterForEventModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _RegisterForEventModal(
          event: event,
          attendeeTypes: attendeeTypes,
          onRegistrationComplete: () {
            _loadEvents();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show registration details modal
  void _showRegistrationDetailsModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _RegistrationDetailsModal(
          event: event,
        );
      },
    );
  }

  // Show edit event modal
  void _showEditEventModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _EditEventModal(
          event: event,
          locations: locations,
          eventTypes: eventTypes,
          onEventUpdated: () {
            _loadEvents();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  // Show event details modal with check-in option
  void _showViewRegistrationModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'View Registration',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cinzel',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are registered for this event!',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Event: ${event.typeName}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Date: ${event.dateRange}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Location: ${event.location}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        Spacer(),
                        // Close button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Close',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEventDetailsModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.registrationActivated && event.registrationDetails != null
                              ? '${event.registrationDetails!['eventName']} (${event.type})'
                              : event.type,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cinzel',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Event Details
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEventDetail('Date', event.dateRange),
                        SizedBox(height: 12),
                        _buildClickableLocationDetail('Location', event.location, event.locationAddress),
                        if (event.registrationActivated && event.registrationDetails != null) ...[
                          SizedBox(height: 16),
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          'Registration Active',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Event: ${event.registrationDetails!['eventName']}',
                                      style: TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                    Text(
                                      'Cost: \$${event.registrationDetails!['cost']}',
                                      style: TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                    if (event.registrationDetails!['preregCost'] != null && event.registrationDetails!['preregCost'] > 0) ...[
                                      Text(
                                        'Prereg Cost: \$${event.registrationDetails!['preregCost']}',
                                        style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                    if (event.registrationDetails!['preregDateEnd'] != null) ...[
                                      Text(
                                        'Prereg Ends: ${_formatDate(event.registrationDetails!['preregDateEnd'])}',
                                        style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                    if (event.registrationDetails!['extraInfo'] != null && event.registrationDetails!['extraInfo'].isNotEmpty) ...[
                                      SizedBox(height: 8),
                                      Text(
                                        'Extra Information:',
                                        style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        event.registrationDetails!['extraInfo'],
                                        style: TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        Spacer(),
                        // Buttons
                        Column(
                          children: [
                            // Admin Registration Button
                            if (isSuperAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    if (event.registrationActivated) {
                                      _showEditRegistrationModal(event); // Edit registration
                                    } else {
                                      _showActivateRegistrationModal(event); // Activate registration
                                    }
                                  },
                                  icon: Icon(event.registrationActivated ? Icons.edit : Icons.add),
                                  label: Text(event.registrationActivated ? 'Edit Registration' : 'Activate Registration'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: event.registrationActivated ? Colors.blue : Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            // User Registration Button (only show if not already registered and not super admin)
                            if (event.registrationActivated && !isSuperAdmin && !(eventRegistrationStatus[event.id] ?? false)) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showRegisterForEventModal(event); // Show registration modal
                                  },
                                  icon: Icon(Icons.person_add),
                                  label: Text('Register for Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            // Registration Details Button (show for all users when registration is active)
                            if (event.registrationActivated) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showRegistrationDetailsModal(event); // Show registration details modal
                                  },
                                  icon: Icon(Icons.list_alt),
                                  label: Text('Registration Details'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            // View Registration Button (only show if already registered and not super admin)
                            if (event.registrationActivated && !isSuperAdmin && (eventRegistrationStatus[event.id] ?? false)) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showViewRegistrationModal(event); // Show view registration modal
                                  },
                                  icon: Icon(Icons.visibility),
                                  label: Text('View Registration'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            // Edit Event Button (Admin only)
                            if (isSuperAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showEditEventModal(event); // Show edit event modal
                                  },
                                  icon: Icon(Icons.edit),
                                  label: Text('Edit Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            // Check In Button (Admin only)
                            if (isSuperAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showCheckInModal(event); // Open QR scanner
                                  },
                                  icon: Icon(Icons.qr_code_scanner),
                                  label: Text('Check In Players'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.black,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              // Debug reset button (only show if check-in is stuck)
                              if (isProcessingCheckIn) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      print('🔄 Manually resetting check-in state');
                                      setState(() {
                                        isProcessingCheckIn = false;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Check-in state reset'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    },
                                    icon: Icon(Icons.refresh),
                                    label: Text('Reset Check-in State (Debug)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.black,
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 12),
                              ],
                            ],
                            // Delete Event Button (Admin only)
                            if (isSuperAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Close details modal
                                    _showDeleteEventConfirmation(event); // Show delete confirmation
                                  },
                                  icon: Icon(Icons.delete),
                                  label: Text('Delete Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                            ],

                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteEventConfirmation(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Delete Event',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            'Are you sure you want to delete "${event.registrationActivated && event.registrationDetails != null ? '${event.registrationDetails!['eventName']} (${event.type})' : event.type}"? This action cannot be undone.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteEvent(event);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteEvent(Event event) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/deleteEvent'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': event.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Event deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadEvents(); // Refresh the events list
        } else {
          throw Exception(data['error'] ?? 'Failed to delete event');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error deleting event: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting event: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncEventsToDiscord() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Syncing Events to Discord'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing events to Discord...'),
              ],
            ),
          );
        },
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/syncEventsToDiscord'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({}),
      );

      // Close loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final summary = data['summary'];
          final results = data['results'] as List;
          
          // Show results dialog
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Discord Sync Results'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Summary:'),
                      Text('• Total events: ${summary['total']}'),
                      Text('• Successful: ${summary['successful']}'),
                      Text('• Updated: ${summary['updated']}'),
                      Text('• Errors: ${summary['errors']}'),
                      Text('• Skipped: ${summary['skipped']}'),
                      SizedBox(height: 16),
                      if (results.isNotEmpty) ...[
                        Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        ...results.map((result) => Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${result['eventName']}: ${result['status']} - ${result['message']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: result['status'] == 'success' ? Colors.green : 
                                     result['status'] == 'updated' ? Colors.blue :
                                     result['status'] == 'error' ? Colors.red : Colors.orange,
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK'),
                  ),
                ],
              );
            },
          );
          
          // Refresh events to show Discord sync status
          _loadEvents();
        } else {
          throw Exception(data['error'] ?? 'Failed to sync events');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error syncing events to Discord: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error syncing events to Discord: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildEventDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      print('❌ Error parsing date: $dateString - $e');
      return dateString; // Return original string if parsing fails
    }
  }

  Widget _buildClickableLocationDetail(String label, String locationName, String address) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        GestureDetector(
          onTap: () => _openLocationInMaps(address),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  locationName,
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Icon(
                Icons.directions,
                color: Colors.amber,
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Manual reset function for stuck check-in state
  void _resetCheckInState() {
    print('🔄 Manually resetting check-in state');
    if (mounted) {
      setState(() {
        isProcessingCheckIn = false;
      });
    }
  }

  // Show check-in modal with scan button
  void _showCheckInModal(Event event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Check In - ${event.registrationActivated && event.registrationDetails != null ? '${event.registrationDetails!['eventName']} (${event.type})' : event.type}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cinzel',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 120,
                          color: Colors.white,
                        ),
                        SizedBox(height: 40),
                        Text(
                          'Event Check-In',
                          style: TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Scan player QR codes to check them in',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 60),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _openCameraScanner(event);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt, size: 24),
                              SizedBox(width: 12),
                              Text(
                                'Start Scanning',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        // Debug reset button
                        if (isProcessingCheckIn) ...[
                          ElevatedButton(
                            onPressed: () {
                              _resetCheckInState();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Check-in state reset'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            ),
                            child: Text('Reset Check-in State (Debug)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Open camera scanner for event check-in
  void _openCameraScanner(Event event) {
    print('📱 Opening camera scanner for event: ${event.id}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EventCameraScannerPage(
          event: event,
          onQRCodeScanned: (qrData) {
            print('📱 Camera scanner callback received: "$qrData"');
            print('📱 Camera scanner callback length: ${qrData.length}');
            Navigator.pop(context);
            _processCheckInQR(context, event, qrData);
          },
        ),
      ),
    );
  }

  // Process check-in QR code
  void _processCheckInQR(BuildContext context, Event event, String qrData) {
    try {
      print('🔍 Processing check-in QR code for event: ${event.id}');
      print('🔍 QR data length: ${qrData.length}');
      print('🔍 QR data: "$qrData"');
      
      // Check if QR data is empty or null
      if (qrData.isEmpty || qrData.trim().isEmpty) {
        print('❌ QR data is empty or contains only whitespace');
        _showCheckInResultWithScanOption('Invalid QR Code', 'QR code data is empty. Please try scanning again.', false, event);
        return;
      }
      
      // Try to parse QR data
      Map<String, dynamic> qrDataMap;
      try {
        qrDataMap = json.decode(qrData);
        print('🔍 Parsed QR data: $qrDataMap');
      } catch (jsonError) {
        print('❌ JSON parsing error: $jsonError');
        print('❌ Raw QR data that failed to parse: "$qrData"');
        _showCheckInResultWithScanOption('Invalid QR Code', 'QR code data is not in the expected format. Please try scanning again.', false, event);
        return;
      }
      
      // Check if it's a valid Crucible QR code
      if (qrDataMap['game'] != 'Crucible') {
        print('❌ Invalid QR code - not from Crucible: ${qrDataMap['game']}');
        _showCheckInResultWithScanOption('Invalid QR Code', 'This QR code is not from Crucible.', false, event);
        return;
      }

      final playerUid = qrDataMap['playerUid'];
      if (playerUid == null) {
        print('❌ QR code missing player UID');
        _showCheckInResultWithScanOption('Invalid QR Code', 'QR code does not contain player UID.', false, event);
        return;
      }

      print('✅ Valid QR code found for player: $playerUid');
      // Check if player is registered for this event
      _checkPlayerRegistrationAndCheckIn(context, event, playerUid, qrDataMap);

    } catch (e) {
      print('❌ Error processing QR code: $e');
      print('❌ Error type: ${e.runtimeType}');
      _showCheckInResultWithScanOption('Error', 'Failed to process QR code: $e', false, event);
    }
  }

  Future<void> _checkPlayerRegistrationAndCheckIn(BuildContext context, Event event, String playerUid, Map<String, dynamic> qrDataMap) async {
    // Prevent multiple simultaneous check-in operations
    if (isProcessingCheckIn) {
      print('⚠️ Check-in already in progress, ignoring duplicate request');
      return;
    }

    if (!mounted) {
      print('⚠️ Widget is no longer mounted, aborting check-in');
      return;
    }

    setState(() {
      isProcessingCheckIn = true;
    });

    // Set a timeout to automatically reset the flag after 30 seconds
    Timer(Duration(seconds: 30), () {
      if (isProcessingCheckIn && mounted) {
        print('⏰ Check-in timeout reached, resetting state');
        setState(() {
          isProcessingCheckIn = false;
        });
      }
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      print('🔍 Checking registration for player: $playerUid, event: ${event.id}');
      final idToken = await user.getIdToken();

      // Check if player is registered for this event
      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkPlayerRegistration'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': event.id,
          'playerUid': playerUid,
          'qrData': qrDataMap,
        }),
      );

      print('🔍 Registration check response status: ${response.statusCode}');
      print('🔍 Registration check response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final isRegistered = data['isRegistered'] ?? false;
          final isCheckedIn = data['isCheckedIn'] ?? false;
          final playerName = data['playerName'] ?? 'Unknown Player';

          // Validate that we can properly identify the player
          if (playerName == 'Unknown Player' || playerName.isEmpty) {
            _showCheckInResultWithScanOption(
              'Player Not Found', 
              'Unable to identify this player. Please ensure they have a valid character profile in the system.', 
              false, 
              event
            );
            return;
          }

          if (!isRegistered) {
            print('🔍 Player is not registered, showing unregistered dialog');
            _showUnregisteredPlayerDialog(event, playerUid, playerName, qrDataMap);
          } else if (isCheckedIn) {
            print('🔍 Player is already checked in');
            _showCheckInResultWithScanOption('Already Checked In', '$playerName is already checked in for this event.', false, event);
          } else {
            print('🔍 Player is registered but not checked in, proceeding with check-in');
            _performCheckIn(event, playerUid, playerName, qrDataMap);
          }
        } else {
          throw Exception(data['error'] ?? 'Failed to check registration');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error checking player registration: $error');
      _showCheckInResultWithScanOption('Error', 'Failed to check player registration: $error', false, event);
    } finally {
      print('🚀 Resetting isProcessingCheckIn to false (registration check)');
      if (mounted) {
        setState(() {
          isProcessingCheckIn = false;
        });
        print('🚀 isProcessingCheckIn reset to false, ready for next operation');
      } else {
        print('⚠️ Widget not mounted, cannot reset isProcessingCheckIn');
      }
    }
  }

  void _showUnregisteredPlayerDialog(Event event, String playerUid, String playerName, Map<String, dynamic> qrDataMap) {
    // Additional validation for unregistered players
    if (playerName == 'Unknown Player' || playerName.isEmpty) {
      _showCheckInResultWithScanOption(
        'Player Not Found', 
        'Unable to identify this player. Please ensure they have a valid character profile in the system.', 
        false, 
        event
      );
      return;
    }
    
    EventAttendeeType? selectedAttendeeType;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(
                'Player Not Registered',
                style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$playerName is not registered for this event. Please select how they are attending:',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<EventAttendeeType>(
                    value: selectedAttendeeType,
                    style: TextStyle(color: Colors.white),
                    dropdownColor: Colors.grey[800],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select attendee type',
                      hintStyle: TextStyle(color: Colors.grey),
                      labelText: 'Attendee Type',
                      labelStyle: TextStyle(color: Colors.amber),
                    ),
                    items: attendeeTypes.map((attendeeType) {
                      return DropdownMenuItem<EventAttendeeType>(
                        value: attendeeType,
                        child: Text(attendeeType.name),
                      );
                    }).toList(),
                    onChanged: (EventAttendeeType? value) {
                      setState(() {
                        selectedAttendeeType = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select an attendee type';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: selectedAttendeeType == null ? null : () {
                    Navigator.of(context).pop();
                                               _performCheckInWithAttendeeType(event, playerUid, playerName, selectedAttendeeType!, qrDataMap);
                  },
                  child: Text('Check In Anyway', style: TextStyle(color: Colors.amber)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performCheckIn(Event event, String playerUid, String playerName, Map<String, dynamic> qrDataMap) async {
    print('🔍 _performCheckIn called for $playerName');
    await _performCheckInWithAttendeeType(event, playerUid, playerName, null, qrDataMap);
  }

  Future<void> _performCheckInWithAttendeeType(Event event, String playerUid, String playerName, EventAttendeeType? attendeeType, Map<String, dynamic> qrDataMap) async {
    print('🚀 Starting check-in process for player: $playerName ($playerUid)');
    print('🚀 Event: ${event.id} - ${event.type}');
    print('🚀 Attendee type: ${attendeeType?.name ?? 'Registered player'}');
    
    if (!mounted) {
      print('⚠️ Widget is no longer mounted, aborting check-in');
      return;
    }

    // Show initial progress dialog
    _showCheckInProgressDialog('Initializing check-in...');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Update progress
      _updateCheckInProgress('Getting authentication token...');
      final idToken = await user.getIdToken();

      // Update progress
      _updateCheckInProgress('Preparing check-in data...');
      final requestBody = {
        'eventId': event.id,
        'playerUid': playerUid,
        'qrData': qrDataMap,
      };

      // Add attendee type info if provided (for unregistered players)
      if (attendeeType != null) {
        requestBody['attendeeTypeId'] = attendeeType.id;
        requestBody['attendeeTypeName'] = attendeeType.name;
        requestBody['buildForEvent'] = attendeeType.buildForEvent.toString();
        requestBody['affinityPointsForEvent'] = attendeeType.affinityPointsForEvent.toString();
      }

      // Update progress
      _updateCheckInProgress('Sending check-in request...');
      print('📡 Sending check-in request to Firebase Function...');
      print('📡 Request body: ${json.encode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkInPlayer'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('📡 Check-in response status: ${response.statusCode}');
      print('📡 Check-in response body: ${response.body}');
      
      // Update progress
      _updateCheckInProgress('Processing response...');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Check-in response parsed successfully: $data');
        
        if (data['ok'] == true) {
          print('✅ Check-in successful!');
          // Update progress
          _updateCheckInProgress('Check-in successful!');
          
          // Close progress dialog and show success
          Navigator.of(context).pop(); // Close progress dialog
          
          // Get attendee type info for the success message
          String attendeeInfo = 'Unknown';
          if (attendeeType != null) {
            attendeeInfo = '${attendeeType.name} (${attendeeType.buildForEvent} Build, ${attendeeType.affinityPointsForEvent} AP)';
          } else {
            // Try to get from response data if available
            final data = json.decode(response.body);
            if (data['sheetsData'] != null) {
              final sheetsData = data['sheetsData'];
              attendeeInfo = '${sheetsData['attendingAs']} (${sheetsData['buildAdjustment']} Build, ${sheetsData['apAdjustment']} AP)';
            }
          }
          
          print('✅ Check-in completed successfully for $playerName');
          
          // Verify the check-in was recorded
          _verifyCheckInRecorded(event, playerUid, playerName);
          
          _showCheckInResultWithScanOption(
            'Check In Successful', 
            '$playerName has been checked in for ${event.type}.\n\nAttending as: $attendeeInfo\n\nData has been recorded in the Event Attending sheet with Event Name: ${event.registrationActivated && event.registrationDetails != null ? event.registrationDetails!['eventName'] : event.type}', 
            true, 
            event
          );
        } else {
          print('❌ Check-in failed: ${data['error']}');
          throw Exception(data['error'] ?? 'Failed to check in player');
        }
      } else {
        print('❌ HTTP error: ${response.statusCode} - ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error checking in player: $error');
      
      // Close progress dialog and show error
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close progress dialog
      }
      _showCheckInResultWithScanOption('Error', 'Failed to check in player: $error', false, event);
    }
  }

  // Progress dialog state
  String _currentProgressMessage = '';

  void _showCheckInProgressDialog(String initialMessage) {
    _currentProgressMessage = initialMessage;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Processing Check-In',
                style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentProgressMessage,
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 16),
              LinearProgressIndicator(
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateCheckInProgress(String message) {
    if (mounted) {
      setState(() {
        _currentProgressMessage = message;
      });
    }
  }

  Future<void> _verifyCheckInRecorded(Event event, String playerUid, String playerName) async {
    try {
      print('🔍 Verifying check-in was recorded for $playerName...');
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ Cannot verify check-in - user not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      
      // Check if player is now checked in
      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkPlayerRegistration'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': event.id,
          'playerUid': playerUid,
          'qrData': {},
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final isCheckedIn = data['isCheckedIn'] ?? false;
          print('🔍 Verification result: isCheckedIn = $isCheckedIn');
          
          if (isCheckedIn) {
            print('✅ Check-in verification successful - player is confirmed checked in');
          } else {
            print('❌ Check-in verification failed - player is not checked in');
          }
        } else {
          print('❌ Verification failed: ${data['error']}');
        }
      } else {
        print('❌ Verification HTTP error: ${response.statusCode}');
      }
    } catch (error) {
      print('❌ Error verifying check-in: $error');
    }
  }

  void _showCheckInResult(String title, String message, bool isSuccess) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            message,
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK', style: TextStyle(color: isSuccess ? Colors.green : Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  void _showCheckInResultWithScanOption(String title, String message, bool isSuccess, Event event) {
    print('📱 Showing check-in result dialog: $title - $message (Success: $isSuccess)');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            message,
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('📱 User clicked "Done" - closing dialogs');
                // Close this dialog and the QR scanner modal
                Navigator.of(context).pop(); // Close result dialog
                Navigator.of(context).pop(); // Close QR scanner modal
              },
              child: Text('Done', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                print('📱 User clicked "Scan Another" - keeping scanner open');
                Navigator.of(context).pop(); // Close result dialog
                // QR scanner stays open for another scan
              },
              child: Text('Scan Another', style: TextStyle(color: Colors.amber)),
            ),
          ],
        );
      },
    );
  }

  // Show scanned QR data (legacy method - keeping for compatibility)
  void _showScannedQRData(BuildContext context, String qrData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Scanned QR Code',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'QR Code Content:',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Text(
                      qrData,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Note: This is a preview. Check-in functionality will be implemented later.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Events',
          style: TextStyle(
            color: Colors.amber,
            fontFamily: 'Cinzel',
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        actions: [
          // Add Event button for super admins
          if (isSuperAdmin && !isLoadingPermissions)
            TextButton.icon(
              icon: Icon(Icons.add, color: Colors.amber),
              label: Text('Add Event', style: TextStyle(color: Colors.amber)),
              onPressed: _showCreateEventModal,
            ),
          // Edit Event Type button for super admins
          if (isSuperAdmin && !isLoadingPermissions)
            TextButton.icon(
              icon: Icon(Icons.category, color: Colors.amber),
              label: Text('Edit Event Type', style: TextStyle(color: Colors.amber)),
              onPressed: _showEventTypeListModal,
            ),
          // Edit Locations button for super admins
          if (isSuperAdmin && !isLoadingPermissions)
            TextButton.icon(
              icon: Icon(Icons.location_on, color: Colors.amber),
              label: Text('Edit Locations', style: TextStyle(color: Colors.amber)),
              onPressed: _showLocationListModal,
            ),
          // Sync to Discord button for super admins
          if (isSuperAdmin && !isLoadingPermissions)
            TextButton.icon(
              icon: Icon(Icons.sync, color: Colors.amber),
              label: Text('Sync to Discord', style: TextStyle(color: Colors.amber)),
              onPressed: _syncEventsToDiscord,
            ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            )
          : events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No events found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEvents,
                  color: Colors.amber,
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _EventCard(
                        event: event,
                        onCheckIn: _showEventDetailsModal,
                      );
                    },
                  ),
                ),
    );
  }

  String _formatGeneratedAt(String generatedAt) {
    try {
      final dateTime = DateTime.parse(generatedAt);
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _openLocationInMaps(String address) async {
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No address available for this location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final Uri mapsUri = Uri.parse(
      'https://maps.google.com/maps?q=${Uri.encodeComponent(address)}'
    );

    try {
      if (kIsWeb) {
        // For web, open in new tab
        // html.window.open(mapsUri.toString(), '_blank');
      } else {
        // For mobile, use url_launcher
        if (await canLaunchUrl(mapsUri)) {
          await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open maps application'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening maps: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Create Event Modal
class _CreateEventModal extends StatefulWidget {
  final List<Location> locations;
  final List<EventType> eventTypes;
  final VoidCallback onEventCreated;

  const _CreateEventModal({
    required this.locations,
    required this.eventTypes,
    required this.onEventCreated,
  });

  @override
  _CreateEventModalState createState() => _CreateEventModalState();
}

class _CreateEventModalState extends State<_CreateEventModal> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  Location? _selectedLocation;
  EventType? _selectedType;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create New Event',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Start Date
                      Text(
                        'Start Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _startDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select start date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // End Date
                      Text(
                        'End Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: _startDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _endDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                _endDate != null
                                    ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select end date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Location
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Location',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                DropdownButtonFormField<Location>(
                                  value: _selectedLocation,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  dropdownColor: Colors.grey[800],
                                  style: TextStyle(color: Colors.white),
                                  hint: Text('Select location', style: TextStyle(color: Colors.grey)),
                                  items: widget.locations.map((location) {
                                    return DropdownMenuItem(
                                      value: location,
                                      child: Text(location.name),
                                    );
                                  }).toList(),
                                  onChanged: (Location? value) {
                                    setState(() {
                                      _selectedLocation = value;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                                                     IconButton(
                             icon: Icon(Icons.add, color: Colors.amber),
                             onPressed: () async {
                               // Show location creation modal
                               final result = await showDialog(
                                 context: context,
                                 builder: (BuildContext context) {
                                   return _CreateLocationModal(
                                     onLocationCreated: () async {
                                       // Refresh locations list
                                       await _refreshLocations();
                                     },
                                   );
                                 },
                               );
                               
                               // If location was created successfully, refresh the dropdown
                               if (result == true) {
                                 await _refreshLocations();
                               }
                             },
                           ),
                        ],
                      ),
                      SizedBox(height: 16),
                      // Event Type
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Event Type',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                DropdownButtonFormField<EventType>(
                                  value: _selectedType,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  dropdownColor: Colors.grey[800],
                                  style: TextStyle(color: Colors.white),
                                  hint: Text('Select event type', style: TextStyle(color: Colors.grey)),
                                  items: widget.eventTypes.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(type.name),
                                    );
                                  }).toList(),
                                  onChanged: (EventType? value) {
                                    setState(() {
                                      _selectedType = value;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                                                     IconButton(
                             icon: Icon(Icons.add, color: Colors.amber),
                             onPressed: () async {
                               // Show event type creation modal
                               final result = await showDialog(
                                 context: context,
                                 builder: (BuildContext context) {
                                   return _CreateEventTypeModal(
                                     onEventTypeCreated: () async {
                                       // Refresh event types list
                                       await _refreshEventTypes();
                                     },
                                   );
                                 },
                               );
                               
                               // If event type was created successfully, refresh the dropdown
                               if (result == true) {
                                 await _refreshEventTypes();
                               }
                             },
                           ),
                        ],
                      ),
                      Spacer(),
                      // Create Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createEvent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                )
                              : Text(
                                  'Create Event',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshLocations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getLocations'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final locationsList = data['locations'] as List;
          final loadedLocations = locationsList.map((locationData) {
            return Location.fromFirestore(locationData, locationData['id']);
          }).toList();

          setState(() {
            widget.locations.clear();
            widget.locations.addAll(loadedLocations);
          });
        }
      }
    } catch (error) {
      print('❌ Error refreshing locations: $error');
    }
  }

  Future<void> _refreshEventTypes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final typesList = data['types'] as List;
          final loadedTypes = typesList.map((typeData) {
            return EventType.fromFirestore(typeData, typeData['id']);
          }).toList();

          setState(() {
            widget.eventTypes.clear();
            widget.eventTypes.addAll(loadedTypes);
          });
        }
      }
    } catch (error) {
      print('❌ Error refreshing event types: $error');
    }
  }

  Future<void> _createEvent() async {
    if (_formKey.currentState!.validate() &&
        _startDate != null &&
        _endDate != null &&
        _selectedLocation != null &&
        _selectedType != null) {
      
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/createEvent'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'startDate': '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            'endDate': '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
            'locationId': _selectedLocation!.id,
            'typeId': _selectedType!.id,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Event created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onEventCreated();
          } else {
            throw Exception(data['error'] ?? 'Failed to create event');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating event: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// Create Location Modal
class _CreateLocationModal extends StatefulWidget {
  final VoidCallback onLocationCreated;

  const _CreateLocationModal({
    required this.onLocationCreated,
  });

  @override
  _CreateLocationModalState createState() => _CreateLocationModalState();
}

class _CreateLocationModalState extends State<_CreateLocationModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  String _selectedTimezone = 'America/New_York';
  bool _isLoading = false;

  // Common timezones for easy selection
  final List<String> _commonTimezones = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Phoenix',
    'America/Anchorage',
    'Pacific/Honolulu',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Australia/Sydney',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create New Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        'Location Name',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter location name',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a location name';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Address
                      Text(
                        'Address',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _addressController,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter address',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an address';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Timezone
                      Text(
                        'Timezone',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedTimezone,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: Colors.grey[800],
                        style: TextStyle(color: Colors.white),
                        items: _commonTimezones.map((timezone) {
                          return DropdownMenuItem(
                            value: timezone,
                            child: Text(timezone.replaceAll('_', ' ')),
                          );
                        }).toList(),
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _selectedTimezone = value;
                            });
                          }
                        },
                      ),
                      Spacer(),
                      // Create Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                )
                              : Text(
                                  'Create Location',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createLocation() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/createLocation'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'name': _nameController.text,
            'address': _addressController.text,
            'timezone': _selectedTimezone,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Location created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onLocationCreated();
            Navigator.of(context).pop(true); // Return true to indicate success
          } else {
            throw Exception(data['error'] ?? 'Failed to create location');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error creating location: $error');
        // Don't show error message here to avoid widget disposal issues
        // The parent widget can handle error display if needed
      } finally {
        // Don't call setState here to avoid widget disposal issues
        // The loading state will be reset when the modal is closed anyway
      }
    }
  }
}

// Create Event Type Modal
class _CreateEventTypeModal extends StatefulWidget {
  final VoidCallback onEventTypeCreated;

  const _CreateEventTypeModal({
    required this.onEventTypeCreated,
  });

  @override
  _CreateEventTypeModalState createState() => _CreateEventTypeModalState();
}

class _CreateEventTypeModalState extends State<_CreateEventTypeModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _defaultCostController = TextEditingController();
  final _defaultPreregCostController = TextEditingController();
  final _numberOfNpcShiftsController = TextEditingController();
  final _numberOfCleanupShiftsController = TextEditingController();
  final List<Map<String, dynamic>> _npcShifts = [];
  final List<String> _cleanupShifts = [];
  final List<String> _payOptions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Set default values
    _defaultCostController.text = '0';
    _defaultPreregCostController.text = '0';
    _numberOfNpcShiftsController.text = '0';
    _numberOfCleanupShiftsController.text = '0';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _defaultCostController.dispose();
    _defaultPreregCostController.dispose();
    _numberOfNpcShiftsController.dispose();
    _numberOfCleanupShiftsController.dispose();
    super.dispose();
  }

  void _addNpcShift() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String? selectedDay;
        TimeOfDay? startTime;
        TimeOfDay? endTime;
        
        final daysOfWeek = [
          'Monday', 'Tuesday', 'Wednesday', 'Thursday', 
          'Friday', 'Saturday', 'Sunday'
        ];
        
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Add NPC Shift',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Day of Week Selection
              DropdownButtonFormField<String>(
                value: selectedDay,
                style: TextStyle(color: Colors.white),
                dropdownColor: Colors.grey[800],
                decoration: InputDecoration(
                  labelText: 'Day of Week',
                  labelStyle: TextStyle(color: Colors.amber),
                  border: OutlineInputBorder(),
                ),
                items: daysOfWeek.map((day) {
                  return DropdownMenuItem<String>(
                    value: day,
                    child: Text(day),
                  );
                }).toList(),
                onChanged: (String? value) {
                  selectedDay = value;
                },
              ),
              SizedBox(height: 16),
              // Start Time
              ListTile(
                title: Text('Start Time', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  startTime != null ? startTime.format(context) : 'Tap to select',
                  style: TextStyle(color: Colors.grey),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null) {
                    startTime = time;
                  }
                },
              ),
              // End Time
              ListTile(
                title: Text('End Time', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  endTime != null ? endTime.format(context) : 'Tap to select',
                  style: TextStyle(color: Colors.grey),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null) {
                    endTime = time;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (selectedDay != null && startTime != null && endTime != null) {
                  setState(() {
                    _npcShifts.add({
                      'dayOfWeek': selectedDay,
                      'startTime': '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}',
                      'endTime': '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}',
                    });
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _addCleanupShift() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final controller = TextEditingController();
        
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Add Cleanup Shift',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g., Monster Camp cleanup',
              hintStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() {
                    _cleanupShifts.add(controller.text);
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _addPayOption() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final controller = TextEditingController();
        
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Add Pay Option',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g., Credit Card, Cash, etc.',
              hintStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() {
                    _payOptions.add(controller.text);
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  String _formatNpcShiftTime(Map<String, dynamic> shift) {
    try {
      // Check if this is the new format (dayOfWeek + time strings)
      if (shift.containsKey('dayOfWeek') && shift.containsKey('startTime') && shift.containsKey('endTime')) {
        return '${shift['dayOfWeek']} ${shift['startTime']} - ${shift['endTime']}';
      }
      
      // Check if this is the old format (DateTime objects)
      if (shift.containsKey('startTime') && shift.containsKey('endTime')) {
        // Try to parse as DateTime (old format)
        final startTime = DateTime.parse(shift['startTime']);
        final endTime = DateTime.parse(shift['endTime']);
        return '${startTime.toString().substring(0, 16)} - ${endTime.toString().substring(0, 16)}';
      }
      
      // Fallback
      return 'Unknown format';
    } catch (e) {
      // If parsing fails, it might be the new time string format
      if (shift.containsKey('startTime') && shift.containsKey('endTime')) {
        return '${shift['startTime']} - ${shift['endTime']}';
      }
      return 'Invalid format';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.category, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create Event Type',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Type Name
                      _buildTextField(
                        controller: _nameController,
                        label: 'Event Type Name',
                        hint: 'Enter event type name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Event type name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Default Cost
                      _buildTextField(
                        controller: _defaultCostController,
                        label: 'Default Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Default cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Default Prereg Cost
                      _buildTextField(
                        controller: _defaultPreregCostController,
                        label: 'Default Preregistration Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Default preregistration cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Number of NPC Shifts
                      _buildTextField(
                        controller: _numberOfNpcShiftsController,
                        label: 'Number of NPC Shifts Required',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Number of NPC shifts is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 24),
                      // NPC Shifts Section
                      Row(
                        children: [
                          Text(
                            'NPC Shifts',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber),
                            onPressed: _addNpcShift,
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_npcShifts.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _npcShifts.asMap().entries.map((entry) {
                              final index = entry.key;
                              final shift = entry.value;
                              return ListTile(
                                title: Text(
                                  'Shift ${index + 1}',
                                  style: TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  _formatNpcShiftTime(shift),
                                  style: TextStyle(color: Colors.grey),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _npcShifts.removeAt(index);
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      SizedBox(height: 24),
                      // Number of Cleanup Shifts
                      _buildTextField(
                        controller: _numberOfCleanupShiftsController,
                        label: 'Number of Cleanup Shifts Required',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Number of cleanup shifts is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 24),
                      // Cleanup Shifts Section
                      Row(
                        children: [
                          Text(
                            'Cleanup Shifts',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber),
                            onPressed: _addCleanupShift,
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_cleanupShifts.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _cleanupShifts.asMap().entries.map((entry) {
                              final index = entry.key;
                              final shift = entry.value;
                              return ListTile(
                                title: Text(
                                  shift,
                                  style: TextStyle(color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _cleanupShifts.removeAt(index);
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      SizedBox(height: 24),
                      // Pay Options Section
                      Row(
                        children: [
                          Text(
                            'Pay Options',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber),
                            onPressed: _addPayOption,
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_payOptions.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _payOptions.asMap().entries.map((entry) {
                              final index = entry.key;
                              final option = entry.value;
                              return ListTile(
                                title: Text(
                                  option,
                                  style: TextStyle(color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _payOptions.removeAt(index);
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      SizedBox(height: 24),
                      // Create Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createEventType,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                )
                              : Text(
                                  'Create Event Type',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildMultiLineTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
            alignLabelWithHint: true,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _createEventType() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/createEventType'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'name': _nameController.text,
            'defaultCost': double.parse(_defaultCostController.text),
            'defaultPreregCost': double.parse(_defaultPreregCostController.text),
            'numberOfNpcShifts': int.parse(_numberOfNpcShiftsController.text),
            'npcShifts': _npcShifts,
            'numberOfCleanupShifts': int.parse(_numberOfCleanupShiftsController.text),
            'cleanupShifts': _cleanupShifts,
            'payOptions': _payOptions,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            // Close the dialog first
            Navigator.of(context).pop(true);
            
            // Then show success message and refresh
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Event type created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onEventTypeCreated();
          } else {
            throw Exception(data['error'] ?? 'Failed to create event type');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error creating event type: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating event type: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
}

// Activate Registration Modal
class _ActivateRegistrationModal extends StatefulWidget {
  final Event event;
  final List<EventType> eventTypes;
  final VoidCallback onRegistrationActivated;

  const _ActivateRegistrationModal({
    required this.event,
    required this.eventTypes,
    required this.onRegistrationActivated,
  });

  @override
  _ActivateRegistrationModalState createState() => _ActivateRegistrationModalState();
}

class _ActivateRegistrationModalState extends State<_ActivateRegistrationModal> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _eventImageController = TextEditingController();
  final _costController = TextEditingController();
  final _preregCostController = TextEditingController();
  final _extraInfoController = TextEditingController();
  DateTime? _preregDateEnd;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEventTypeDefaults();
  }

  void _loadEventTypeDefaults() {
    // Find the event type for this event
    final eventType = widget.eventTypes.firstWhere(
      (type) => type.name == widget.event.typeName,
      orElse: () => EventType(id: '', name: ''),
    );

    if (eventType.id.isNotEmpty) {
      // Pre-populate with event type defaults
      _costController.text = eventType.defaultCost.toString();
      _preregCostController.text = eventType.defaultPreregCost.toString();
      // Note: Build fields are now handled by Event Attendee Types
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _shortNameController.dispose();
    _eventImageController.dispose();
    _costController.dispose();
    _preregCostController.dispose();
    _extraInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Activate Event Registration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Name
                      _buildTextField(
                        controller: _eventNameController,
                        label: 'Event Name',
                        hint: 'Enter the full name of the event',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Event name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Short Name
                      _buildTextField(
                        controller: _shortNameController,
                        label: 'Short Name',
                        hint: 'Used for Discord channel (lowercase, numbers, hyphens only)',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Short name is required';
                          }
                          if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                            return 'Only lowercase letters, numbers, and hyphens allowed';
                          }
                          if (value.length > 32) {
                            return 'Short name must be 32 characters or less';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Event Image
                      _buildTextField(
                        controller: _eventImageController,
                        label: 'Event Image URL',
                        hint: 'Link to a PNG image (optional)',
                      ),
                      SizedBox(height: 16),
                      // Cost
                      _buildTextField(
                        controller: _costController,
                        label: 'Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Prereg Cost
                      _buildTextField(
                        controller: _preregCostController,
                        label: 'Preregistration Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Preregistration cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Extra Info
                      _buildMultiLineTextField(
                        controller: _extraInfoController,
                        label: 'Extra Information',
                        hint: 'Enter any additional information',
                      ),
                      SizedBox(height: 16),
                      // Prereg Date End
                      Text(
                        'Preregistration End Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _preregDateEnd = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                _preregDateEnd != null
                                    ? '${_preregDateEnd!.year}-${_preregDateEnd!.month.toString().padLeft(2, '0')}-${_preregDateEnd!.day.toString().padLeft(2, '0')}'
                                    : 'Select preregistration end date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      // Activate Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _activateRegistration,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Activate Registration',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildMultiLineTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
            alignLabelWithHint: true,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _activateRegistration() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/activateEventRegistration'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'eventId': widget.event.id,
            'eventName': _eventNameController.text,
            'shortName': _shortNameController.text,
            'eventImage': _eventImageController.text,
            'cost': double.parse(_costController.text),
            'preregCost': double.parse(_preregCostController.text),
            'preregDateEnd': _preregDateEnd?.toIso8601String(),
            'extraInfo': _extraInfoController.text,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Registration activated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onRegistrationActivated();
          } else {
            throw Exception(data['error'] ?? 'Failed to activate registration');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error activating registration: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error activating registration: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// Edit Registration Modal
class _EditRegistrationModal extends StatefulWidget {
  final Event event;
  final VoidCallback onRegistrationUpdated;

  const _EditRegistrationModal({
    required this.event,
    required this.onRegistrationUpdated,
  });

  @override
  _EditRegistrationModalState createState() => _EditRegistrationModalState();
}

class _EditRegistrationModalState extends State<_EditRegistrationModal> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _eventImageController = TextEditingController();
  final _costController = TextEditingController();
  final _preregCostController = TextEditingController();
  final _extraInfoController = TextEditingController();
  DateTime? _preregDateEnd;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.event.registrationDetails != null) {
      final details = widget.event.registrationDetails!;
      _eventNameController.text = details['eventName'] ?? '';
      _shortNameController.text = details['shortName'] ?? '';
      _eventImageController.text = details['eventImage'] ?? '';
      _costController.text = (details['cost'] ?? 0).toString();
      _preregCostController.text = (details['preregCost'] ?? 0).toString();
      _extraInfoController.text = details['extraInfo'] ?? '';
      
      if (details['preregDateEnd'] != null) {
        _preregDateEnd = DateTime.parse(details['preregDateEnd']);
      }
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _shortNameController.dispose();
    _eventImageController.dispose();
    _costController.dispose();
    _preregCostController.dispose();
    _extraInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Event Registration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Name
                      _buildTextField(
                        controller: _eventNameController,
                        label: 'Event Name',
                        hint: 'Enter the full name of the event',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Event name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Short Name
                      _buildTextField(
                        controller: _shortNameController,
                        label: 'Short Name',
                        hint: 'Used for Discord channel (lowercase, numbers, hyphens only)',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Short name is required';
                          }
                          if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                            return 'Only lowercase letters, numbers, and hyphens allowed';
                          }
                          if (value.length > 32) {
                            return 'Short name must be 32 characters or less';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Event Image
                      _buildTextField(
                        controller: _eventImageController,
                        label: 'Event Image URL',
                        hint: 'Link to a PNG image (optional)',
                      ),
                      SizedBox(height: 16),
                      // Cost
                      _buildTextField(
                        controller: _costController,
                        label: 'Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Prereg Cost
                      _buildTextField(
                        controller: _preregCostController,
                        label: 'Preregistration Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Preregistration cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Prereg Date End
                      Text(
                        'Preregistration End Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _preregDateEnd ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _preregDateEnd = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                _preregDateEnd != null
                                    ? '${_preregDateEnd!.year}-${_preregDateEnd!.month.toString().padLeft(2, '0')}-${_preregDateEnd!.day.toString().padLeft(2, '0')}'
                                    : 'Select preregistration end date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Extra Info
                      _buildMultiLineTextField(
                        controller: _extraInfoController,
                        label: 'Extra Information',
                        hint: 'Enter any additional information',
                      ),
                      SizedBox(height: 24),
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateRegistration,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Update Registration',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildMultiLineTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
            alignLabelWithHint: true,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _updateRegistration() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/updateEventRegistration'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'eventId': widget.event.id,
            'eventName': _eventNameController.text,
            'shortName': _shortNameController.text,
            'eventImage': _eventImageController.text,
            'cost': double.parse(_costController.text),
            'preregCost': double.parse(_preregCostController.text),
            'preregDateEnd': _preregDateEnd?.toIso8601String(),
            'extraInfo': _extraInfoController.text,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Registration updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onRegistrationUpdated();
          } else {
            throw Exception(data['error'] ?? 'Failed to update registration');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error updating registration: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating registration: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

class _EventCard extends StatefulWidget {
  final Event event;
  final Function(Event) onCheckIn;

  const _EventCard({required this.event, required this.onCheckIn});

  @override
  _EventCardState createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool isLoadingPermissions = false;
  bool hasAdminPermissions = false;
  bool isRegistered = false;
  bool isLoadingRegistration = false;
  bool isCheckedIn = false;
  bool isLoadingCheckIn = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkRegistrationStatus();
    _checkCheckInStatus();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      isLoadingPermissions = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ No authenticated user found');
        setState(() {
          hasAdminPermissions = false;
          isLoadingPermissions = false;
        });
        return;
      }

      print('🔍 Checking permissions for user: ${user.uid} (${user.email})');

      // Check if user is a super admin
      final superAdminDoc = await _firestore
          .collection('roles')
          .doc('superadmin')
          .collection('members')
          .doc(user.uid)
          .get();
      
      print('🔍 Super admin check result: ${superAdminDoc.exists}');
      
      if (superAdminDoc.exists) {
        print('✅ User is super admin');
        if (mounted) {
          setState(() {
            hasAdminPermissions = true;
            isLoadingPermissions = false;
          });
        }
        return;
      }

      // Check if user is registered for this specific event
      // Use event type as short name for now
      final eventShortName = widget.event.type.toLowerCase().replaceAll(' ', '_');
      print('🔍 Checking event registration for: $eventShortName');
      
      final eventRegistrationDoc = await _firestore
          .collection('events')
          .doc(eventShortName)
          .collection('registrations')
          .doc(user.uid)
          .get();
      
      print('🔍 Event registration check result: ${eventRegistrationDoc.exists}');
      
      if (mounted) {
        setState(() {
          hasAdminPermissions = eventRegistrationDoc.exists;
          isLoadingPermissions = false;
        });
      }
      
      if (eventRegistrationDoc.exists) {
        print('✅ User is registered for event: $eventShortName');
      } else {
        print('❌ User is not registered for event: $eventShortName');
      }
    } catch (e) {
      print('❌ Error checking permissions: $e');
      if (mounted) {
        setState(() {
          hasAdminPermissions = false;
          isLoadingPermissions = false;
        });
      }
    }
  }

  Future<void> _checkRegistrationStatus() async {
    if (mounted) {
      setState(() {
        isLoadingRegistration = true;
      });
    }

    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            isRegistered = false;
            isLoadingRegistration = false;
          });
        }
        return;
      }

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getUserEventRegistration?eventId=${widget.event.id}'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          if (mounted) {
            setState(() {
              isRegistered = data['registered'] ?? false;
              isLoadingRegistration = false;
            });
          }
        }
      }
    } catch (error) {
      print('❌ Error checking registration status: $error');
      if (mounted) {
        setState(() {
          isRegistered = false;
          isLoadingRegistration = false;
        });
      }
    }
  }

  Future<void> _checkCheckInStatus() async {
    if (mounted) {
      setState(() {
        isLoadingCheckIn = true;
      });
    }

    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            isCheckedIn = false;
            isLoadingCheckIn = false;
          });
        }
        return;
      }

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkPlayerRegistration'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': widget.event.id,
          'playerUid': user.uid,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          if (mounted) {
            setState(() {
              isCheckedIn = data['isCheckedIn'] ?? false;
              isLoadingCheckIn = false;
            });
          }
        }
      }
    } catch (error) {
      print('❌ Error checking check-in status: $error');
      if (mounted) {
        setState(() {
          isCheckedIn = false;
          isLoadingCheckIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final eventStart = widget.event.startDateTime;
    final isUpcoming = eventStart.isAfter(now);
    final isPast = widget.event.endDateTime.isBefore(now);

    return GestureDetector(
      onTap: (hasAdminPermissions || (widget.event.registrationActivated && !isLoadingPermissions)) 
          ? () => widget.onCheckIn(widget.event)
          : null,
      child: Card(
        margin: EdgeInsets.only(bottom: 16),
        color: Colors.grey[900],
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isUpcoming 
                  ? Colors.amber 
                  : isPast 
                      ? Colors.grey 
                      : Colors.green,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.event.registrationActivated && widget.event.registrationDetails != null
                            ? '${widget.event.registrationDetails!['eventName']} (${widget.event.type})'
                            : widget.event.type,
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cinzel',
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isUpcoming 
                            ? Colors.amber.withOpacity(0.2)
                            : isPast 
                                ? Colors.grey.withOpacity(0.2)
                                : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isUpcoming 
                            ? 'Upcoming'
                            : isPast 
                                ? 'Past'
                                : 'Ongoing',
                        style: TextStyle(
                          color: isUpcoming 
                              ? Colors.amber
                              : isPast 
                                  ? Colors.grey
                                  : Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: Colors.white70,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      widget.event.dateRange,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _openLocationInMaps(widget.event.locationAddress),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.amber,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.event.location,
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 16,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.directions,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ],
                  ),
                ),
                if (isUpcoming) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: Colors.amber,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '${_getDaysUntilEvent(eventStart)} days until event',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Loading indicator for permissions check
                if (isLoadingPermissions) ...[
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Checking permissions...',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                // Registration status
                if (widget.event.registrationActivated && !isLoadingRegistration) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isRegistered 
                          ? Colors.green.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isRegistered ? Colors.green : Colors.blue,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isRegistered ? Icons.check_circle : Icons.event_available,
                          color: isRegistered ? Colors.green : Colors.blue,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          isRegistered ? 'Registered' : 'Registration Open',
                          style: TextStyle(
                            color: isRegistered ? Colors.green : Colors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Check-in status
                if (widget.event.registrationActivated && isRegistered && !isLoadingCheckIn) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCheckedIn 
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isCheckedIn ? Colors.green : Colors.orange,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCheckedIn ? Icons.check_circle : Icons.pending,
                          color: isCheckedIn ? Colors.green : Colors.orange,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          isCheckedIn ? 'Checked In' : 'Not Checked In',
                          style: TextStyle(
                            color: isCheckedIn ? Colors.green : Colors.orange,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Loading indicator for check-in check
                if (widget.event.registrationActivated && isRegistered && isLoadingCheckIn) ...[
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Checking check-in status...',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                // Loading indicator for registration check
                if (widget.event.registrationActivated && isLoadingRegistration) ...[
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Checking registration...',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _getDaysUntilEvent(DateTime eventDate) {
    final now = DateTime.now();
    final difference = eventDate.difference(now);
    return difference.inDays;
  }

  Future<void> _openLocationInMaps(String address) async {
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No address available for this location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final Uri mapsUri = Uri.parse(
      'https://maps.google.com/maps?q=${Uri.encodeComponent(address)}'
    );

    try {
      if (kIsWeb) {
        // For web, open in new tab
        // html.window.open(mapsUri.toString(), '_blank');
      } else {
        // For mobile, use url_launcher
        if (await canLaunchUrl(mapsUri)) {
          await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open maps application'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening maps: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// QR Scanner Widget for check-in
class _QRScannerWidget extends StatefulWidget {
  final Function(String) onQRCodeScanned;

  const _QRScannerWidget({required this.onQRCodeScanned});

  @override
  _QRScannerWidgetState createState() => _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<_QRScannerWidget> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        widget.onQRCodeScanned(scanData.code!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Scan a player\'s QR code to check them in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Cinzel',
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(Icons.flash_on, color: Colors.white),
                      onPressed: () async {
                        await controller?.toggleFlash();
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.flip_camera_ios, color: Colors.white),
                      onPressed: () async {
                        await controller?.flipCamera();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
} 

// Event Type List Modal
class _EventTypeListModal extends StatefulWidget {
  final List<EventType> eventTypes;
  final VoidCallback onEventTypeUpdated;

  const _EventTypeListModal({
    required this.eventTypes,
    required this.onEventTypeUpdated,
  });

  @override
  _EventTypeListModalState createState() => _EventTypeListModalState();
}

class _EventTypeListModalState extends State<_EventTypeListModal> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.category, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manage Event Types',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, color: Colors.amber),
                    onPressed: () {
                      Navigator.of(context).pop();
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return _CreateEventTypeModal(
                            onEventTypeCreated: () {
                              widget.onEventTypeUpdated();
                            },
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: widget.eventTypes.isEmpty
                  ? Center(
                      child: Text(
                        'No event types found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: widget.eventTypes.length,
                      itemBuilder: (context, index) {
                        final eventType = widget.eventTypes[index];
                        return Card(
                          color: Colors.grey[800],
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              eventType.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Default Cost: \$${eventType.defaultCost}',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                Text(
                                  'Default Prereg Cost: \$${eventType.defaultPreregCost}',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                if (eventType.npcShifts.isNotEmpty)
                                  Text(
                                    'NPC Shifts: ${eventType.npcShifts.length}',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return _EditEventTypeModal(
                                          eventType: eventType,
                                          onEventTypeUpdated: () {
                                            widget.onEventTypeUpdated();
                                          },
                                          onShowMessage: (message) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(message),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _showDeleteConfirmation(eventType),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(EventType eventType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Delete Event Type',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            'Are you sure you want to delete "${eventType.name}"? This action cannot be undone.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteEventType(eventType);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteEventType(EventType eventType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/deleteEventType'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventTypeId': eventType.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          // Show success message before updating
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Event type deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onEventTypeUpdated();
        } else {
          throw Exception(data['error'] ?? 'Failed to delete event type');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error deleting event type: $error');
      if (mounted) {
        String errorMessage = 'Error deleting event type';
        if (error.toString().contains('Cannot delete event type that is being used by existing events')) {
          errorMessage = 'Cannot delete this event type because it is being used by existing events. Please remove it from all events first.';
        } else {
          errorMessage = 'Error deleting event type: $error';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

// Location List Modal
class _LocationListModal extends StatefulWidget {
  final List<Location> locations;
  final VoidCallback onLocationUpdated;

  const _LocationListModal({
    required this.locations,
    required this.onLocationUpdated,
  });

  @override
  _LocationListModalState createState() => _LocationListModalState();
}

class _LocationListModalState extends State<_LocationListModal> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manage Locations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, color: Colors.amber),
                    onPressed: () {
                      Navigator.of(context).pop();
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return _CreateLocationModal(
                            onLocationCreated: () {
                              widget.onLocationUpdated();
                            },
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: widget.locations.isEmpty
                  ? Center(
                      child: Text(
                        'No locations found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: widget.locations.length,
                      itemBuilder: (context, index) {
                        final location = widget.locations[index];
                        return Card(
                          color: Colors.grey[800],
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              location.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  location.address,
                                  style: TextStyle(color: Colors.grey),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Timezone: ${location.timezone.replaceAll('_', ' ')}',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return _EditLocationModal(
                                          location: location,
                                          onLocationUpdated: () {
                                            widget.onLocationUpdated();
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _showDeleteConfirmation(location),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Location location) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Delete Location',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            'Are you sure you want to delete "${location.name}"? This action cannot be undone.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteLocation(location);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteLocation(Location location) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/deleteLocation'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'locationId': location.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onLocationUpdated();
        } else {
          throw Exception(data['error'] ?? 'Failed to delete location');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error deleting location: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting location: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Edit Event Type Modal
class _EditEventTypeModal extends StatefulWidget {
  final EventType eventType;
  final VoidCallback onEventTypeUpdated;
  final Function(String) onShowMessage;

  const _EditEventTypeModal({
    required this.eventType,
    required this.onEventTypeUpdated,
    required this.onShowMessage,
  });

  @override
  _EditEventTypeModalState createState() => _EditEventTypeModalState();
}

class _EditEventTypeModalState extends State<_EditEventTypeModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _defaultCostController = TextEditingController();
  final _defaultPreregCostController = TextEditingController();
  final _numberOfNpcShiftsController = TextEditingController();
  List<Map<String, dynamic>> _npcShifts = [];
  List<EventAttendeeType> _attendeeTypes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
    _loadAttendeeTypes();
  }

  void _loadExistingData() {
    _nameController.text = widget.eventType.name;
    _defaultCostController.text = widget.eventType.defaultCost.toString();
    _defaultPreregCostController.text = widget.eventType.defaultPreregCost.toString();
    _numberOfNpcShiftsController.text = widget.eventType.numberOfNpcShifts.toString();
    _npcShifts = List<Map<String, dynamic>>.from(widget.eventType.npcShifts);
  }

  Future<void> _loadAttendeeTypes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventAttendeeTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final attendeeTypesList = data['attendeeTypes'] as List;
          final loadedAttendeeTypes = attendeeTypesList.map((attendeeTypeData) {
            return EventAttendeeType.fromFirestore(attendeeTypeData, attendeeTypeData['id']);
          }).toList();

          setState(() {
            _attendeeTypes = loadedAttendeeTypes;
          });
        }
      }
    } catch (error) {
      print('❌ Error loading attendee types: $error');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _defaultCostController.dispose();
    _defaultPreregCostController.dispose();
    _numberOfNpcShiftsController.dispose();
    super.dispose();
  }

  String _formatNpcShiftTime(Map<String, dynamic> shift) {
    try {
      // Check if this is the new format (dayOfWeek + time strings)
      if (shift.containsKey('dayOfWeek') && shift.containsKey('startTime') && shift.containsKey('endTime')) {
        return '${shift['dayOfWeek']} ${shift['startTime']} - ${shift['endTime']}';
      }
      
      // Check if this is the old format (DateTime objects)
      if (shift.containsKey('startTime') && shift.containsKey('endTime')) {
        // Try to parse as DateTime (old format)
        final startTime = DateTime.parse(shift['startTime']);
        final endTime = DateTime.parse(shift['endTime']);
        return '${startTime.toString().substring(0, 16)} - ${endTime.toString().substring(0, 16)}';
      }
      
      // Fallback
      return 'Unknown format';
    } catch (e) {
      // If parsing fails, it might be the new time string format
      if (shift.containsKey('startTime') && shift.containsKey('endTime')) {
        return '${shift['startTime']} - ${shift['endTime']}';
      }
      return 'Invalid format';
    }
  }

  void _addNpcShift() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        DateTime? startTime;
        DateTime? endTime;
        
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Add NPC Shift',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Start Time', style: TextStyle(color: Colors.white)),
                subtitle: Text('Tap to select', style: TextStyle(color: Colors.grey)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(Duration(days: 365)),
                  );
                  if (date != null) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      startTime = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    }
                  }
                },
              ),
              ListTile(
                title: Text('End Time', style: TextStyle(color: Colors.white)),
                subtitle: Text('Tap to select', style: TextStyle(color: Colors.grey)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(Duration(days: 365)),
                  );
                  if (date != null) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      endTime = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (startTime != null && endTime != null) {
                  setState(() {
                    _npcShifts.add({
                      'startTime': startTime!.toIso8601String(),
                      'endTime': endTime!.toIso8601String(),
                    });
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Event Type',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Type Name
                      _buildTextField(
                        controller: _nameController,
                        label: 'Event Type Name',
                        hint: 'Enter event type name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Event type name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Default Cost
                      _buildTextField(
                        controller: _defaultCostController,
                        label: 'Default Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Default cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Default Prereg Cost
                      _buildTextField(
                        controller: _defaultPreregCostController,
                        label: 'Default Preregistration Cost (\$)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Default preregistration cost is required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Number of NPC Shifts
                      _buildTextField(
                        controller: _numberOfNpcShiftsController,
                        label: 'Number of NPC Shifts Required',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Number of NPC shifts is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 24),
                      // Event Attendee Types Section
                      Row(
                        children: [
                          Text(
                            'Event Attendee Types',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber),
                            onPressed: () => _showCreateAttendeeTypeModal(),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_attendeeTypes.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _attendeeTypes.map((attendeeType) {
                              return ListTile(
                                title: Text(
                                  attendeeType.name,
                                  style: TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  'Build: ${attendeeType.buildForEvent}, Affinity: ${attendeeType.affinityPointsForEvent}, Max Consume: ${attendeeType.maxConsumeForEvent}',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                                      onPressed: () => _showEditAttendeeTypeModal(attendeeType),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () => _showDeleteAttendeeTypeConfirmation(attendeeType),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'No attendee types defined. Click + to add one.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                      SizedBox(height: 24),
                      // NPC Shifts Section
                      Row(
                        children: [
                          Text(
                            'NPC Shifts',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber),
                            onPressed: _addNpcShift,
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Temporarily disabled NPC shifts display due to format issue
                      // if (_npcShifts.isNotEmpty) ...[
                      //   Container(
                      //     padding: EdgeInsets.all(12),
                      //     decoration: BoxDecoration(
                      //       color: Colors.grey[800],
                      //       borderRadius: BorderRadius.circular(8),
                      //     ),
                      //     child: Column(
                      //       children: _npcShifts.asMap().entries.map((entry) {
                      //         final index = entry.key;
                      //         final shift = entry.value;
                      //         return ListTile(
                      //           title: Text(
                      //             'Shift ${index + 1}',
                      //             style: TextStyle(color: Colors.white),
                      //           ),
                      //           subtitle: Text(
                      //             '${DateTime.parse(shift['startTime']).toString().substring(0, 16)} - ${DateTime.parse(shift['endTime']).toString().substring(0, 16)}',
                      //             style: TextStyle(color: Colors.grey),
                      //           ),
                      //           trailing: IconButton(
                      //             icon: Icon(Icons.delete, color: Colors.red),
                      //             onPressed: () {
                      //               setState(() {
                      //                 _npcShifts.removeAt(index);
                      //               });
                      //             },
                      //           ),
                      //         );
                      //       }).toList(),
                      //     ),
                      //   ),
                      // ],
                      SizedBox(height: 24),
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateEventType,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Update Event Type',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildMultiLineTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
            alignLabelWithHint: true,
          ),
          validator: validator,
        ),
      ],
    );
  }

  void _showCreateAttendeeTypeModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _CreateAttendeeTypeModal(
          onAttendeeTypeCreated: () {
            _loadAttendeeTypes();
          },
        );
      },
    );
  }

  void _showEditAttendeeTypeModal(EventAttendeeType attendeeType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _EditAttendeeTypeModal(
          attendeeType: attendeeType,
          onAttendeeTypeUpdated: () {
            _loadAttendeeTypes();
          },
        );
      },
    );
  }

  void _showDeleteAttendeeTypeConfirmation(EventAttendeeType attendeeType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Delete Attendee Type',
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: Text(
            'Are you sure you want to delete "${attendeeType.name}"? This action cannot be undone.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAttendeeType(attendeeType);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAttendeeType(EventAttendeeType attendeeType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/deleteEventAttendeeType'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'attendeeTypeId': attendeeType.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Attendee type deleted successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          _loadAttendeeTypes();
        } else {
          throw Exception(data['error'] ?? 'Failed to delete attendee type');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      print('❌ Error deleting attendee type: $error');
      if (mounted) {
        String errorMessage = 'Error deleting attendee type';
        if (error.toString().contains('Cannot delete attendee type that is being used by existing registrations')) {
          errorMessage = 'Cannot delete this attendee type because it is being used by existing event registrations. Please remove it from all registrations first.';
        } else if (error.toString().contains('FAILED_PRECONDITION')) {
          errorMessage = 'Cannot delete attendee type due to database constraints. It may be in use by existing registrations.';
        } else {
          errorMessage = 'Error deleting attendee type: $error';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _updateEventType() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/updateEventType'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'eventTypeId': widget.eventType.id,
            'name': _nameController.text,
            'defaultCost': double.parse(_defaultCostController.text),
            'defaultPreregCost': double.parse(_defaultPreregCostController.text),
            'numberOfNpcShifts': int.parse(_numberOfNpcShiftsController.text),
            'npcShifts': _npcShifts,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            widget.onEventTypeUpdated();
            Navigator.of(context).pop();
          } else {
            throw Exception(data['error'] ?? 'Failed to update event type');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error updating event type: $error');
        // Don't show error message here to avoid widget disposal issues
        // The parent widget can handle error display if needed
      } finally {
        // Don't call setState here to avoid widget disposal issues
        // The loading state will be reset when the modal is closed anyway
      }
    }
  }
}

// Edit Location Modal
class _EditLocationModal extends StatefulWidget {
  final Location location;
  final VoidCallback onLocationUpdated;

  const _EditLocationModal({
    required this.location,
    required this.onLocationUpdated,
  });

  @override
  _EditLocationModalState createState() => _EditLocationModalState();
}

class _EditLocationModalState extends State<_EditLocationModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  String _selectedTimezone = 'America/New_York';
  bool _isLoading = false;

  // Common timezones for easy selection
  final List<String> _commonTimezones = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Phoenix',
    'America/Anchorage',
    'Pacific/Honolulu',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Australia/Sydney',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    _nameController.text = widget.location.name;
    _addressController.text = widget.location.address;
    _selectedTimezone = widget.location.timezone;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _buildTextField(
                        controller: _nameController,
                        label: 'Location Name',
                        hint: 'Enter location name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Location name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Address
                      _buildTextField(
                        controller: _addressController,
                        label: 'Address',
                        hint: 'Enter location address',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Address is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Timezone
                      Text(
                        'Timezone',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedTimezone,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: Colors.grey[800],
                        style: TextStyle(color: Colors.white),
                        items: _commonTimezones.map((timezone) {
                          return DropdownMenuItem(
                            value: timezone,
                            child: Text(timezone.replaceAll('_', ' ')),
                          );
                        }).toList(),
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _selectedTimezone = value;
                            });
                          }
                        },
                      ),
                      Spacer(),
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Update Location',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _updateLocation() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/updateLocation'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'locationId': widget.location.id,
            'name': _nameController.text,
            'address': _addressController.text,
            'timezone': _selectedTimezone,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            widget.onLocationUpdated();
            Navigator.of(context).pop();
          } else {
            throw Exception(data['error'] ?? 'Failed to update location');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error updating location: $error');
        // Don't show error message here to avoid widget disposal issues
        // The parent widget can handle error display if needed
      } finally {
        // Don't call setState here to avoid widget disposal issues
        // The loading state will be reset when the modal is closed anyway
      }
    }
  }
}

// Create Attendee Type Modal
class _CreateAttendeeTypeModal extends StatefulWidget {
  final VoidCallback onAttendeeTypeCreated;

  const _CreateAttendeeTypeModal({
    required this.onAttendeeTypeCreated,
  });

  @override
  _CreateAttendeeTypeModalState createState() => _CreateAttendeeTypeModalState();
}

class _CreateAttendeeTypeModalState extends State<_CreateAttendeeTypeModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _buildForEventController = TextEditingController();
  final _affinityPointsController = TextEditingController();
  final _maxConsumeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _buildForEventController.text = '0';
    _affinityPointsController.text = '0';
    _maxConsumeController.text = '0';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildForEventController.dispose();
    _affinityPointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_add, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create Attendee Type',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _buildTextField(
                        controller: _nameController,
                        label: 'Attendee Type Name',
                        hint: 'Enter attendee type name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Attendee type name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Build for Event
                      _buildTextField(
                        controller: _buildForEventController,
                        label: 'Build for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Build for event is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Affinity Points
                      _buildTextField(
                        controller: _affinityPointsController,
                        label: 'Affinity Points for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Affinity points is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Max Consume
                      _buildTextField(
                        controller: _maxConsumeController,
                        label: 'Max Consume for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Max consume is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      Spacer(),
                      // Create Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createAttendeeType,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Create Attendee Type',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _createAttendeeType() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/createEventAttendeeType'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'name': _nameController.text,
            'buildForEvent': int.parse(_buildForEventController.text),
            'affinityPointsForEvent': int.parse(_affinityPointsController.text),
            'maxConsumeForEvent': int.parse(_maxConsumeController.text),
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            // Show success message before closing modal
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Attendee type created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onAttendeeTypeCreated();
            Navigator.of(context).pop();
          } else {
            throw Exception(data['error'] ?? 'Failed to create attendee type');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error creating attendee type: $error');
        // Don't show error message here to avoid widget disposal issues
        // The parent widget can handle error display if needed
      } finally {
        // Don't call setState here to avoid widget disposal issues
        // The loading state will be reset when the modal is closed anyway
      }
    }
  }
}

// Edit Attendee Type Modal
class _EditAttendeeTypeModal extends StatefulWidget {
  final EventAttendeeType attendeeType;
  final VoidCallback onAttendeeTypeUpdated;

  const _EditAttendeeTypeModal({
    required this.attendeeType,
    required this.onAttendeeTypeUpdated,
  });

  @override
  _EditAttendeeTypeModalState createState() => _EditAttendeeTypeModalState();
}

class _EditAttendeeTypeModalState extends State<_EditAttendeeTypeModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _buildForEventController = TextEditingController();
  final _affinityPointsController = TextEditingController();
  final _maxConsumeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    _nameController.text = widget.attendeeType.name;
    _buildForEventController.text = widget.attendeeType.buildForEvent.toString();
    _affinityPointsController.text = widget.attendeeType.affinityPointsForEvent.toString();
    _maxConsumeController.text = widget.attendeeType.maxConsumeForEvent.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildForEventController.dispose();
    _affinityPointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Attendee Type',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _buildTextField(
                        controller: _nameController,
                        label: 'Attendee Type Name',
                        hint: 'Enter attendee type name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Attendee type name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Build for Event
                      _buildTextField(
                        controller: _buildForEventController,
                        label: 'Build for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Build for event is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Affinity Points
                      _buildTextField(
                        controller: _affinityPointsController,
                        label: 'Affinity Points for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Affinity points is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      // Max Consume
                      _buildTextField(
                        controller: _maxConsumeController,
                        label: 'Max Consume for Event',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Max consume is required';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      Spacer(),
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateAttendeeType,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Update Attendee Type',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _updateAttendeeType() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/updateEventAttendeeType'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'attendeeTypeId': widget.attendeeType.id,
            'name': _nameController.text,
            'buildForEvent': int.parse(_buildForEventController.text),
            'affinityPointsForEvent': int.parse(_affinityPointsController.text),
            'maxConsumeForEvent': int.parse(_maxConsumeController.text),
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            widget.onAttendeeTypeUpdated();
            Navigator.of(context).pop();
          } else {
            throw Exception(data['error'] ?? 'Failed to update attendee type');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error updating attendee type: $error');
        // Don't show error message here to avoid widget disposal issues
        // The parent widget can handle error display if needed
      } finally {
        // Don't call setState here to avoid widget disposal issues
        // The loading state will be reset when the modal is closed anyway
      }
    }
  }
}

// Edit Event Modal
class _EditEventModal extends StatefulWidget {
  final Event event;
  final List<Location> locations;
  final List<EventType> eventTypes;
  final VoidCallback onEventUpdated;

  const _EditEventModal({
    required this.event,
    required this.locations,
    required this.eventTypes,
    required this.onEventUpdated,
  });

  @override
  _EditEventModalState createState() => _EditEventModalState();
}

class _EditEventModalState extends State<_EditEventModal> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  Location? _selectedLocation;
  EventType? _selectedType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    _startDate = widget.event.startDateTime;
    _endDate = widget.event.endDateTime;
    
    // Find the current location and type
    _selectedLocation = widget.locations.firstWhere(
      (location) => location.name == widget.event.locationName,
      orElse: () => widget.locations.first,
    );
    
    _selectedType = widget.eventTypes.firstWhere(
      (type) => type.name == widget.event.typeName,
      orElse: () => widget.eventTypes.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Event',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Start Date
                      Text(
                        'Start Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _startDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.grey),
                              SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select start date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      // End Date
                      Text(
                        'End Date',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _endDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: Colors.grey),
                              SizedBox(width: 8),
                              Text(
                                _endDate != null
                                    ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select end date',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      // Location Selection
                      Text(
                        'Location',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<Location>(
                        value: _selectedLocation,
                        style: TextStyle(color: Colors.white),
                        dropdownColor: Colors.grey[800],
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select location',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        items: widget.locations.map((location) {
                          return DropdownMenuItem<Location>(
                            value: location,
                            child: Text(location.name),
                          );
                        }).toList(),
                        onChanged: (Location? value) {
                          setState(() {
                            _selectedLocation = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a location';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 24),
                      // Event Type Selection
                      Text(
                        'Event Type',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<EventType>(
                        value: _selectedType,
                        style: TextStyle(color: Colors.white),
                        dropdownColor: Colors.grey[800],
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select event type',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        items: widget.eventTypes.map((type) {
                          return DropdownMenuItem<EventType>(
                            value: type,
                            child: Text(type.name),
                          );
                        }).toList(),
                        onChanged: (EventType? value) {
                          setState(() {
                            _selectedType = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select an event type';
                          }
                          return null;
                        },
                      ),
                      Spacer(),
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateEvent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Update Event',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateEvent() async {
    if (_formKey.currentState!.validate()) {
      if (_startDate == null || _endDate == null || _selectedLocation == null || _selectedType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please fill in all fields'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();

        final response = await http.post(
          Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/updateEvent'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'eventId': widget.event.id,
            'startDate': '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            'endDate': '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
            'locationId': _selectedLocation!.id,
            'typeId': _selectedType!.id,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ok'] == true) {
            // Close the dialog first
            Navigator.of(context).pop();
            
            // Then show success message and refresh
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Event updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            widget.onEventUpdated();
          } else {
            throw Exception(data['error'] ?? 'Failed to update event');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        print('❌ Error updating event: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating event: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
}

// Register for Event Modal
class _RegisterForEventModal extends StatefulWidget {
  final Event event;
  final List<EventAttendeeType> attendeeTypes;
  final VoidCallback onRegistrationComplete;

  const _RegisterForEventModal({
    required this.event,
    required this.attendeeTypes,
    required this.onRegistrationComplete,
  });

  @override
  _RegisterForEventModalState createState() => _RegisterForEventModalState();
}

class _RegisterForEventModalState extends State<_RegisterForEventModal> {
  final _formKey = GlobalKey<FormState>();

  EventAttendeeType? _selectedAttendeeType;
  final List<int> _selectedNpcShifts = [];
  final List<int> _selectedCleanupShifts = [];
  int? _selectedPayOption;
  int _currentStep = 0;
  EventType? _eventType;
  bool _isLoadingEventType = true;
  bool _isSubmitting = false;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadEventType();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadEventType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final typesList = data['types'] as List;
          final eventType = typesList.firstWhere(
            (type) => type['name'] == widget.event.typeName,
            orElse: () => null,
          );
          
          if (eventType != null) {
            setState(() {
              _eventType = EventType.fromFirestore(eventType, eventType['id']);
              _isLoadingEventType = false;
            });
          } else {
            setState(() {
              _isLoadingEventType = false;
            });
          }
        }
      }
    } catch (error) {
      print('❌ Error loading event type: $error');
      setState(() {
        _isLoadingEventType = false;
      });
    }
  }

  Future<EventType?> _getEventType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventTypes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final typesList = data['types'] as List;
          final eventType = typesList.firstWhere(
            (type) => type['name'] == widget.event.typeName,
            orElse: () => null,
          );
          
          if (eventType != null) {
            return EventType.fromFirestore(eventType, eventType['id']);
          }
        }
      }
      return null;
    } catch (error) {
      print('❌ Error getting event type: $error');
      return null;
    }
  }

  int _getTotalSteps() {
    // Always return a consistent number of steps
    // We'll show all possible steps and conditionally enable/disable them
    return 4; // Event info + attendee type + NPC shifts + cleanup shifts + pay options
  }

  bool _canProceedToNextStep() {
    bool canProceed = false;
    switch (_currentStep) {
      case 0:
        canProceed = _selectedAttendeeType != null;
        print('Step 0 validation: attendeeType=${_selectedAttendeeType?.name}, canProceed=$canProceed');
        return canProceed;
      case 1:
        // NPC Shifts step
        if (_eventType != null && _eventType!.numberOfNpcShifts > 0 && _eventType!.npcShifts.isNotEmpty) {
          canProceed = _selectedNpcShifts.length == _eventType!.numberOfNpcShifts;
          print('Step 1 validation: npcShifts=${_selectedNpcShifts.length}/${_eventType!.numberOfNpcShifts}, canProceed=$canProceed');
        } else {
          canProceed = true; // Skip this step if no NPC shifts required or available
          print('Step 1 validation: no NPC shifts required or available, canProceed=$canProceed');
        }
        return canProceed;
      case 2:
        // Cleanup Shifts step
        if (_eventType != null && _eventType!.numberOfCleanupShifts > 0) {
          canProceed = _selectedCleanupShifts.length == _eventType!.numberOfCleanupShifts;
          print('Step 2 validation: cleanupShifts=${_selectedCleanupShifts.length}/${_eventType!.numberOfCleanupShifts}, canProceed=$canProceed');
        } else {
          canProceed = true; // Skip this step if no cleanup shifts required
          print('Step 2 validation: no cleanup shifts required, canProceed=$canProceed');
        }
        return canProceed;
      case 3:
        // Pay Options step
        if (_eventType != null && _eventType!.payOptions.isNotEmpty) {
          canProceed = _selectedPayOption != null;
          print('Step 3 validation: payOption=$_selectedPayOption, canProceed=$canProceed');
        } else {
          canProceed = true; // Skip this step if no pay options required
          print('Step 3 validation: no pay options required, canProceed=$canProceed');
        }
        return canProceed;
      default:
        return true;
    }
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Info
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.event.type,
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  widget.event.dateRange,
                  style: TextStyle(color: Colors.white),
                ),
                Text(
                  widget.event.location,
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          // Attendee Type Selection
          Text(
            'Attendee Type',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          DropdownButtonFormField<EventAttendeeType>(
            value: _selectedAttendeeType,
            style: TextStyle(color: Colors.white),
            dropdownColor: Colors.grey[800],
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Select attendee type',
              hintStyle: TextStyle(color: Colors.grey),
            ),
            items: widget.attendeeTypes.map((attendeeType) {
              return DropdownMenuItem<EventAttendeeType>(
                value: attendeeType,
                child: Text(attendeeType.name),
              );
            }).toList(),
            onChanged: (EventAttendeeType? value) {
              setState(() {
                _selectedAttendeeType = value;
                // Reset dependent selections
                _selectedNpcShifts.clear();
                _selectedCleanupShifts.clear();
                _selectedPayOption = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    if (_isLoadingEventType) {
      return Center(child: CircularProgressIndicator());
    }

    print('Building Step 2: eventType=${_eventType?.name}, numberOfNpcShifts=${_eventType?.numberOfNpcShifts}, npcShifts=${_eventType?.npcShifts.length}');

    if (_eventType != null && _eventType!.numberOfNpcShifts > 0) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Select ${_eventType!.numberOfNpcShifts} NPC shifts:',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _selectedNpcShifts.length == _eventType!.numberOfNpcShifts 
                        ? Colors.green.withOpacity(0.2) 
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedNpcShifts.length == _eventType!.numberOfNpcShifts 
                          ? Colors.green 
                          : Colors.orange,
                    ),
                  ),
                  child: Text(
                    '${_selectedNpcShifts.length}/${_eventType!.numberOfNpcShifts}',
                    style: TextStyle(
                      color: _selectedNpcShifts.length == _eventType!.numberOfNpcShifts 
                          ? Colors.green 
                          : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            if (_eventType!.npcShifts.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: _eventType!.npcShifts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final shift = entry.value;
                    final isSelected = _selectedNpcShifts.contains(index);
                    
                    return CheckboxListTile(
                      title: Text(
                        'Shift ${index + 1}',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${_formatTime(shift['startTime'])} - ${_formatTime(shift['endTime'])}',
                        style: TextStyle(color: Colors.grey),
                      ),
                      value: isSelected,
                      onChanged: (bool? value) {
                        print('NPC shift checkbox changed: index=$index, value=$value, currentSelected=${_selectedNpcShifts.length}/${_eventType!.numberOfNpcShifts}');
                        setState(() {
                          if (value == true) {
                            if (_selectedNpcShifts.length < _eventType!.numberOfNpcShifts) {
                              _selectedNpcShifts.add(index);
                              print('Added NPC shift $index, now selected: $_selectedNpcShifts');
                            }
                          } else {
                            _selectedNpcShifts.remove(index);
                            print('Removed NPC shift $index, now selected: $_selectedNpcShifts');
                          }
                        });
                      },
                      activeColor: Colors.amber,
                      checkColor: Colors.black,
                    );
                  }).toList(),
                ),
              ),
                          if (_selectedNpcShifts.length != _eventType!.numberOfNpcShifts) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please select exactly ${_eventType!.numberOfNpcShifts} NPC shift${_eventType!.numberOfNpcShifts > 1 ? 's' : ''} to continue',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ] else ...[
              Text(
                'No NPC shifts available for this event type',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      return Center(
        child: Text(
          'No NPC shifts required for this event type.',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
      );
    }
  }

  Widget _buildStep3() {
    if (_isLoadingEventType) {
      return Center(child: CircularProgressIndicator());
    }

    if (_eventType != null && _eventType!.numberOfCleanupShifts > 0) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select ${_eventType!.numberOfCleanupShifts} cleanup shifts:',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            if (_eventType!.cleanupShifts.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: _eventType!.cleanupShifts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final shift = entry.value;
                    final isSelected = _selectedCleanupShifts.contains(index);
                    
                    return CheckboxListTile(
                      title: Text(
                        shift,
                        style: TextStyle(color: Colors.white),
                      ),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            if (_selectedCleanupShifts.length < _eventType!.numberOfCleanupShifts) {
                              _selectedCleanupShifts.add(index);
                            }
                          } else {
                            _selectedCleanupShifts.remove(index);
                          }
                        });
                      },
                      activeColor: Colors.amber,
                      checkColor: Colors.black,
                    );
                  }).toList(),
                ),
              ),
              if (_selectedCleanupShifts.length != _eventType!.numberOfCleanupShifts) ...[
                SizedBox(height: 8),
                Text(
                  'Please select exactly ${_eventType!.numberOfCleanupShifts} cleanup shifts',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ] else ...[
              Text(
                'No cleanup shifts available for this event type',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      return Center(
        child: Text(
          'No cleanup shifts required for this event type.',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
      );
    }
  }

  Widget _buildStep4() {
    if (_isLoadingEventType) {
      return Center(child: CircularProgressIndicator());
    }

    if (_eventType != null && _eventType!.payOptions.isNotEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a payment option:',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: _eventType!.payOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final isSelected = _selectedPayOption == index;
                  
                  return RadioListTile<int>(
                    title: Text(
                      option,
                      style: TextStyle(color: Colors.white),
                    ),
                    value: index,
                    groupValue: _selectedPayOption,
                    onChanged: (int? value) {
                      setState(() {
                        _selectedPayOption = value;
                      });
                    },
                    activeColor: Colors.amber,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Text(
          'No payment options required for this event type.',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
              child: Row(
                children: [
                  Icon(Icons.person_add, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Register for Event',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Step Indicator
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: List.generate(4, (index) {
                  final isActive = index == _currentStep;
                  final isCompleted = index < _currentStep;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: isCompleted 
                            ? Colors.green 
                            : isActive 
                                ? Colors.blue 
                                : Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: [
                  // Step 1: Event Info + Attendee Type
                  _buildStep1(),
                  // Step 2: NPC Shifts
                  _buildStep2(),
                  // Step 3: Cleanup Shifts
                  _buildStep3(),
                  // Step 4: Pay Options
                  _buildStep4(),
                ],
              ),
            ),
            // Navigation Buttons
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _currentStep--;
                        });
                        _pageController.animateToPage(
                          _currentStep,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Text('Back'),
                    ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: (_canProceedToNextStep() && !_isSubmitting) 
                        ? () {
                            print('Button pressed: currentStep=$_currentStep, canProceed=${_canProceedToNextStep()}');
                            if (_currentStep == 3) {
                              print('Calling _registerForEvent()');
                              _registerForEvent();
                            } else {
                              print('Moving to next step: $_currentStep -> ${_currentStep + 1}');
                              setState(() {
                                _currentStep++;
                              });
                              _pageController.animateToPage(
                                _currentStep,
                                duration: Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          }
                        : null,
                    child: _currentStep == 3 && _isSubmitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Submitting...'),
                            ],
                          )
                        : Text(_currentStep == 3 ? 'Submit' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.amber,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Future<void> _registerForEvent() async {
    // Set loading state
    setState(() {
      _isSubmitting = true;
    });

    // Validate attendee type is selected
    if (_selectedAttendeeType == null) {
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select an attendee type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate NPC shifts if required
    if (_eventType != null && _eventType!.numberOfNpcShifts > 0) {
      if (_selectedNpcShifts.length != _eventType!.numberOfNpcShifts) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select exactly ${_eventType!.numberOfNpcShifts} NPC shifts'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validate cleanup shifts if required
    if (_eventType != null && _eventType!.numberOfCleanupShifts > 0) {
      if (_selectedCleanupShifts.length != _eventType!.numberOfCleanupShifts) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select exactly ${_eventType!.numberOfCleanupShifts} cleanup shifts'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validate pay option if required
    if (_eventType != null && _eventType!.payOptions.isNotEmpty) {
      if (_selectedPayOption == null) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select a pay option'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/registerForEvent'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': widget.event.id,
          'attendeeTypeId': _selectedAttendeeType!.id,
          'selectedNpcShifts': _selectedNpcShifts,
          'selectedCleanupShifts': _selectedCleanupShifts,
          'selectedPayOption': _selectedPayOption,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          setState(() {
            _isSubmitting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully registered for event!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onRegistrationComplete();
        } else {
          throw Exception(data['error'] ?? 'Failed to register for event');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      setState(() {
        _isSubmitting = false;
      });
      print('❌ Error registering for event: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error registering for event: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatTime(String timeString) {
    try {
      // If it's already a time string like "23:00", return it as is
      if (timeString.contains(':') && !timeString.contains('-')) {
        return timeString;
      }
      
      // If it's a full datetime string, parse it and extract time
      final dateTime = DateTime.parse(timeString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      print('❌ Error formatting time: $timeString - $e');
      return timeString; // Return original string if parsing fails
    }
  }
}

// Registration Details Modal
class _RegistrationDetailsModal extends StatefulWidget {
  final Event event;

  const _RegistrationDetailsModal({
    required this.event,
  });

  @override
  _RegistrationDetailsModalState createState() => _RegistrationDetailsModalState();
}

class _RegistrationDetailsModalState extends State<_RegistrationDetailsModal> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _registrationData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRegistrationData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRegistrationData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEventRegistrations?eventId=${widget.event.id}'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          setState(() {
            _registrationData = data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (error) {
      print('❌ Error loading registration data: $error');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.list_alt, color: Colors.purple),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registration Details - ${widget.event.type}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Tab Bar
            Container(
              color: Colors.grey[800],
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.purple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.purple,
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'NPC Shifts'),
                  Tab(text: 'Cleanup'),
                ],
              ),
            ),
            // Tab Content
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDetailsTab(),
                        _buildNpcShiftsTab(),
                        _buildCleanupTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    if (_registrationData == null) {
      return Center(
        child: Text(
          'No registration data available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final registrations = _registrationData!['registrations'] as Map<String, dynamic>? ?? {};
    final totalRegistrations = registrations['total'] as int? ?? 0;
    final players = registrations['players'] as int? ?? 0;
    final sliceOfLife = registrations['sliceOfLife'] as int? ?? 0;
    final staff = registrations['staff'] as int? ?? 0;

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registration Summary',
            style: TextStyle(
              color: Colors.purple,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          InkWell(
            onTap: () => _showAttendeeTypeDetails('Players', _registrationData!['registrations']['registrations'] as List, 'Player'),
            child: _buildSummaryCard('Players', players.toString(), Icons.person),
          ),
          SizedBox(height: 8),
          InkWell(
            onTap: () => _showAttendeeTypeDetails('Slice of Life', _registrationData!['registrations']['registrations'] as List, 'Slice of Life'),
            child: _buildSummaryCard('Slice of Life', sliceOfLife.toString(), Icons.emoji_emotions),
          ),
          SizedBox(height: 8),
          InkWell(
            onTap: () => _showAttendeeTypeDetails('Staff', _registrationData!['registrations']['registrations'] as List, 'Staff'),
            child: _buildSummaryCard('Staff', staff.toString(), Icons.work),
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: () => _showAllRegistrations('All Registrations', _registrationData!['registrations']['registrations'] as List),
            child: _buildSummaryCard('Total Registrations', totalRegistrations.toString(), Icons.people),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String count, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.purple, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              count,
              style: TextStyle(
                color: Colors.purple,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNpcShiftsTab() {
    if (_registrationData == null) {
      return Center(
        child: Text(
          'No registration data available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final npcShifts = _registrationData!['npcShifts'] as Map<String, dynamic>? ?? {};
    
    if (npcShifts.isEmpty) {
      return Center(
        child: Text(
          'No NPC shifts available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: npcShifts.length,
        itemBuilder: (context, index) {
          final shiftKey = npcShifts.keys.elementAt(index);
          final shiftData = npcShifts[shiftKey] as Map<String, dynamic>;
          final shiftName = shiftData['name'] as String? ?? 'Shift ${index + 1}';
          final registrations = shiftData['registrations'] as List? ?? [];
          final count = registrations.length;

          return Card(
            color: Colors.grey[800],
            margin: EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.schedule, color: Colors.orange),
              title: Text(
                shiftName,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '$count people registered',
                style: TextStyle(color: Colors.grey),
              ),
              trailing: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () => _showShiftDetails(shiftName, registrations),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCleanupTab() {
    if (_registrationData == null) {
      return Center(
        child: Text(
          'No registration data available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final cleanupTasks = _registrationData!['cleanupTasks'] as Map<String, dynamic>? ?? {};
    
    if (cleanupTasks.isEmpty) {
      return Center(
        child: Text(
          'No cleanup tasks available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: cleanupTasks.length,
        itemBuilder: (context, index) {
          final taskKey = cleanupTasks.keys.elementAt(index);
          final taskData = cleanupTasks[taskKey] as Map<String, dynamic>;
          final taskName = taskData['name'] as String? ?? 'Task ${index + 1}';
          final registrations = taskData['registrations'] as List? ?? [];
          final count = registrations.length;

          return Card(
            color: Colors.grey[800],
            margin: EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.cleaning_services, color: Colors.green),
              title: Text(
                taskName,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '$count people registered',
                style: TextStyle(color: Colors.grey),
              ),
              trailing: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () => _showCleanupDetails(taskName, registrations),
            ),
          );
        },
      ),
    );
  }

  void _showShiftDetails(String shiftName, List registrations) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            shiftName,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: registrations.isEmpty
                ? Text(
                    'No one registered for this shift',
                    style: TextStyle(color: Colors.grey),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: registrations.length,
                    itemBuilder: (context, index) {
                      final registration = registrations[index];
                      final playerName = registration['playerName'] as String? ?? 'Unknown Player';
                      final characterName = registration['characterName'] as String? ?? '';
                      
                      return ListTile(
                        leading: Icon(Icons.person, color: Colors.orange),
                        title: Text(
                          playerName,
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: characterName.isNotEmpty ? Text(
                          characterName,
                          style: TextStyle(color: Colors.grey),
                        ) : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.purple)),
            ),
          ],
        );
      },
    );
  }

  void _showCleanupDetails(String taskName, List registrations) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            taskName,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: registrations.isEmpty
                ? Text(
                    'No one registered for this task',
                    style: TextStyle(color: Colors.grey),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: registrations.length,
                    itemBuilder: (context, index) {
                      final registration = registrations[index];
                      final playerName = registration['playerName'] as String? ?? 'Unknown Player';
                      final characterName = registration['characterName'] as String? ?? '';
                      
                      return ListTile(
                        leading: Icon(Icons.person, color: Colors.green),
                        title: Text(
                          playerName,
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: characterName.isNotEmpty ? Text(
                          characterName,
                          style: TextStyle(color: Colors.grey),
                        ) : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.purple)),
            ),
          ],
        );
      },
    );
  }

  void _showAttendeeTypeDetails(String title, List allRegistrations, String attendeeType) {
    // Filter registrations by attendee type
    final filteredRegistrations = allRegistrations.where((registration) {
      final registrationAttendeeType = registration['attendeeTypeName'] as String? ?? '';
      return registrationAttendeeType.toLowerCase() == attendeeType.toLowerCase();
    }).toList();

    // Sort by player name alphabetically
    filteredRegistrations.sort((a, b) {
      final nameA = (a['playerName'] as String? ?? '').toLowerCase();
      final nameB = (b['playerName'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: filteredRegistrations.isEmpty
                ? Text(
                    'No $attendeeType registrations found',
                    style: TextStyle(color: Colors.grey),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredRegistrations.length,
                    itemBuilder: (context, index) {
                      final registration = filteredRegistrations[index];
                      final playerName = registration['playerName'] as String? ?? 'Unknown Player';
                      final characterName = registration['characterName'] as String? ?? '';
                      
                      return ListTile(
                        leading: Icon(Icons.person, color: Colors.purple),
                        title: Text(
                          playerName,
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: characterName.isNotEmpty ? Text(
                          characterName,
                          style: TextStyle(color: Colors.grey),
                        ) : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.purple)),
            ),
          ],
        );
      },
    );
  }

  void _showAllRegistrations(String title, List allRegistrations) {
    // Sort by player name alphabetically
    final sortedRegistrations = List.from(allRegistrations);
    sortedRegistrations.sort((a, b) {
      final nameA = (a['playerName'] as String? ?? '').toLowerCase();
      final nameB = (b['playerName'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: sortedRegistrations.isEmpty
                ? Text(
                    'No registrations found',
                    style: TextStyle(color: Colors.grey),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: sortedRegistrations.length,
                    itemBuilder: (context, index) {
                      final registration = sortedRegistrations[index];
                      final playerName = registration['playerName'] as String? ?? 'Unknown Player';
                      final characterName = registration['characterName'] as String? ?? '';
                      final attendeeType = registration['attendeeTypeName'] as String? ?? 'Unknown';
                      
                      return ListTile(
                        leading: Icon(Icons.person, color: Colors.purple),
                        title: Text(
                          playerName,
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (characterName.isNotEmpty)
                              Text(
                                characterName,
                                style: TextStyle(color: Colors.grey),
                              ),
                            Text(
                              attendeeType,
                              style: TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.purple)),
            ),
          ],
        );
      },
    );
  }
}

// Event Camera Scanner Page
class _EventCameraScannerPage extends StatefulWidget {
  final Event event;
  final Function(String) onQRCodeScanned;

  const _EventCameraScannerPage({
    required this.event,
    required this.onQRCodeScanned,
  });

  @override
  _EventCameraScannerPageState createState() => _EventCameraScannerPageState();
}

class _EventCameraScannerPageState extends State<_EventCameraScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? lastScannedCode;
  DateTime? lastScanTime;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      print('📱 QR Scanner: Received scan data');
      print('📱 QR Scanner: scanData.code = "${scanData.code}"');
      print('📱 QR Scanner: scanData.code is null = ${scanData.code == null}');
      
      if (scanData.code != null) {
        print('📱 QR Scanner: Calling _handleQRCodeScan with: "${scanData.code}"');
        _handleQRCodeScan(scanData.code!);
      } else {
        print('📱 QR Scanner: scanData.code is null, ignoring scan');
      }
    });
  }

  void _handleQRCodeScan(String qrCode) {
    print('📱 QR Scanner: _handleQRCodeScan called with: "$qrCode"');
    print('📱 QR Scanner: qrCode length: ${qrCode.length}');
    
    final now = DateTime.now();
    
    // Debounce: Ignore scans of the same code within 2 seconds
    if (lastScannedCode == qrCode && 
        lastScanTime != null && 
        now.difference(lastScanTime!).inSeconds < 2) {
      print('📱 QR Scanner: Debouncing duplicate scan');
      return;
    }
    
    // Update last scan info
    lastScannedCode = qrCode;
    lastScanTime = now;
    
    print('📱 QR Scanner: Calling widget.onQRCodeScanned with: "$qrCode"');
    // Call the callback to pass the QR code back to the main page
    widget.onQRCodeScanned(qrCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Event Check-In Scanner'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on),
            onPressed: () async {
              await controller?.toggleFlash();
            },
          ),
          IconButton(
            icon: Icon(Icons.flip_camera_ios),
            onPressed: () async {
              await controller?.flipCamera();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Point camera at player QR code',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      widget.event.type,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}