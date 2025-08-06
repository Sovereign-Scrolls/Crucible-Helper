import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/event.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  _EventsPageState createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  EventsData? eventsData;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchEvents();
  }

  Future<void> fetchEvents() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final ref = FirebaseStorage.instance.ref().child('Events/events.json');
      final data = await ref.getData();
      
      if (data != null) {
        final jsonString = utf8.decode(data);
        print('Raw JSON string: $jsonString'); // Debug: Print raw JSON
        
        final dynamic jsonData = json.decode(jsonString);
        print('Parsed JSON type: ${jsonData.runtimeType}'); // Debug: Print JSON type
        
        EventsData events;
        
        if (jsonData is Map<String, dynamic>) {
          // Expected format: {"events": [...], "generatedAt": "...", "version": "..."}
          events = EventsData.fromJson(jsonData);
        } else if (jsonData is List) {
          // Your current format: direct array of events
          events = EventsData(
            events: jsonData.map((eventJson) => Event.fromJson(eventJson)).toList(),
            generatedAt: DateTime.now().toIso8601String(),
            version: '1.0.0',
          );
        } else {
          throw Exception('Unexpected JSON format: ${jsonData.runtimeType}');
        }
        
        setState(() {
          eventsData = events;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'No events data found';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading events: $e';
        isLoading = false;
      });
      print('Error fetching events: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Events',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: fetchEvents,
            tooltip: 'Refresh Events',
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading events...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            : errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        SizedBox(height: 16),
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: fetchEvents,
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : eventsData?.events.isEmpty == true
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No events scheduled',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontFamily: 'Cinzel',
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          if (eventsData != null) ...[
                            Container(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Version: ${eventsData!.version}',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Last Updated: ${_formatGeneratedAt(eventsData!.generatedAt)}',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                itemCount: eventsData!.events.length,
                                itemBuilder: (context, index) {
                                  final event = eventsData!.events[index];
                                  return _EventCard(event: event);
                                },
                              ),
                            ),
                          ],
                        ],
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
}

class _EventCard extends StatelessWidget {
  final Event event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final eventStart = event.startDateTime;
    final isUpcoming = eventStart.isAfter(now);
    final isPast = event.endDateTime.isBefore(now);

    return Card(
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
                      event.type,
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
                    event.dateRange,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Colors.white70,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.location,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
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
            ],
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
} 