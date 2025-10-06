import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../shared/impersonation_service.dart';
import '../shared/npc_cache_service.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  String _statusMessage = '';
  bool _isImpersonating = false;

  @override
  void initState() {
    super.initState();
    // Initialize impersonation status
    _isImpersonating = ImpersonationService.isImpersonating;
    
    // Listen to impersonation status changes
    ImpersonationService.listenable.addListener(() {
      if (mounted) {
        setState(() {
          _isImpersonating = ImpersonationService.isImpersonating;
        });
      }
    });
  }

  /// Build impersonation banner (reused from main.dart)
  Widget _buildImpersonationBanner() {
    if (!_isImpersonating) return SizedBox.shrink();
    
    final targetEmail = ImpersonationService.targetEmail ?? 'Unknown User';
    final targetUid = ImpersonationService.targetUid ?? '';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade800, Colors.red.shade700],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search,
            color: Colors.white,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🎭 IMPERSONATING USER',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  targetEmail,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
                if (targetUid.isNotEmpty)
                  Text(
                    'UID: ${targetUid.substring(0, 8)}...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              ImpersonationService.stop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Stopped impersonating user'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(Icons.close, color: Colors.white, size: 16),
            label: Text(
              'STOP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.black.withOpacity(0.2),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size(0, 0),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Admin Dashboard',
          style: TextStyle(
            color: Colors.amber,
            fontFamily: 'Cinzel',
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
      ),
      body: Column(
        children: [
          // Impersonation banner (always at top)
          _buildImpersonationBanner(),
          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Data Management'),
            _buildDataManagementSection(),
            SizedBox(height: 32),
            _buildSectionHeader('System Tools'),
            _buildSystemToolsSection(),
            SizedBox(height: 32),
            _buildSectionHeader('NPCs'),
            _buildNPCsSection(),
            SizedBox(height: 32),
                  _buildSectionHeader('Status'),
                  _buildStatusSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.amber,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cinzel',
        ),
      ),
    );
  }

  Widget _buildDataManagementSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAdminAction(
              icon: Icons.sync,
              title: 'Sync Master Log',
              description: 'Synchronize master log data from Google Sheets',
              onPressed: _syncMasterLog,
              color: Colors.blue,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.refresh,
              title: 'Refresh Data Cache',
              description: 'Clear and refresh cached data',
              onPressed: _refreshDataCache,
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemToolsSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAdminAction(
              icon: Icons.verified_user,
              title: 'Manage Permissions',
              description: 'Grant or revoke event check-in permissions',
              onPressed: _showManagePermissions,
              color: Colors.purple,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.person_search,
              title: 'Impersonate User',
              description: 'Temporarily act as another user in the app',
              onPressed: _showImpersonateDialog,
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNPCsSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAdminAction(
              icon: Icons.person_add,
              title: 'Create NPC',
              description: 'Create a new NPC (Cultivator or Monster)',
              onPressed: _showCreateNPCDialog,
              color: Colors.orange,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.list,
              title: 'List NPCs',
              description: 'View all NPCs (Cultivators and Monsters)',
              onPressed: _showListNPCsDialog,
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              Row(
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
                    'Processing...',
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                ],
              ),
            if (_statusMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showManagePermissions() {
    showDialog(
      context: context,
      builder: (context) => _ManagePermissionsDialog(),
    );
  }

  void _showImpersonateDialog() {
    showDialog(
      context: context,
      builder: (context) => _ImpersonateDialog(),
    );
  }

  Widget _buildAdminAction({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          padding: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: color.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _syncMasterLog() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initiating master log sync...';
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      
      setState(() {
        _statusMessage = 'Connecting to sync service...';
      });

      final response = await http.post(
        Uri.parse(AppConfig.syncMasterLogsUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'containerDocId': 'root',
          'sheetName': 'Master Logs',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final stats = data;
          setState(() {
            _statusMessage = '''Master Log Sync Completed Successfully!

📊 Sync Statistics:
• Rows processed: ${stats['written'] ?? 0}
• Characters mirrored: ${stats['mirrored'] ?? 0}
• Records cleared: ${stats['cleared'] ?? 0}
• Obsolete records deleted: ${stats['deletedFromCharacters'] ?? 0}

📋 Diagnostics:
• Total rows processed: ${stats['diagnostics']?['processedRows'] ?? 0}
• Missing character numbers: ${stats['diagnostics']?['missingCharacterNumber'] ?? 0}
• Missing UIDs: ${stats['diagnostics']?['missingUid'] ?? 0}
• Resolved via PC DB: ${stats['diagnostics']?['resolvedViaPcDb'] ?? 0}

🎯 Target: ${stats['sheetName']} (${stats['containerDocId']})
🆔 Spreadsheet: ${stats['spreadsheetId']}''';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Master log sync completed successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Sync failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'HTTP ${response.statusCode}');
      }
    } catch (error) {
      setState(() {
        _statusMessage = 'Error: ${error.toString()}';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${error.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDataCache() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Refreshing data cache...';
    });

    // Simulate cache refresh - you can implement actual cache clearing here
    await Future.delayed(Duration(seconds: 2));

    setState(() {
      _isLoading = false;
      _statusMessage = 'Data cache refreshed successfully!';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Data cache refreshed!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showSystemAnalytics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'System Analytics',
          style: TextStyle(color: Colors.amber),
        ),
        content: Text(
          'System analytics feature coming soon...',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _showConfiguration() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Configuration',
          style: TextStyle(color: Colors.amber),
        ),
        content: Text(
          'Configuration management coming soon...',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  /// Show dialog to create a new NPC
  void _showCreateNPCDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateNPCDialog(),
    );
  }

  /// Show dialog to list all NPCs
  void _showListNPCsDialog() {
    showDialog(
      context: context,
      builder: (context) => _ListNPCsDialog(),
    );
  }
}

class _ManagePermissionsDialog extends StatefulWidget {
  @override
  State<_ManagePermissionsDialog> createState() => _ManagePermissionsDialogState();
}

class _ManagePermissionsDialogState extends State<_ManagePermissionsDialog> {
  final TextEditingController _eventIdController = TextEditingController();
  bool _loading = false;
  List<dynamic> _global = [];
  List<dynamic> _eventMembers = [];
  List<dynamic> _users = [];
  String? _selectedUserUid;
  String _selectedPermission = 'single_event_checkin';
  List<Map<String, String>> _activeEvents = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() { _loading = true; });
    try {
      await Future.wait([
        _loadUsers(),
        _loadActiveEvents(),
        _loadPermissions(),
      ]);
    } catch (_) {} finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      setState(() { _loading = true; });
      final resp = await http.get(
        Uri.parse(AppConfig.listCheckInPermissionsUrl + (_eventIdController.text.isNotEmpty ? '?eventId=${_eventIdController.text}' : '')),
        headers: { 'Authorization': 'Bearer $idToken' },
      );
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true) {
          setState(() { _global = body['global'] ?? []; _eventMembers = body['eventMembers'] ?? []; });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _grant({required bool global}) async {
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) return;
      final idToken = await user.getIdToken();
      setState(() { _loading = true; });
      final resp = await http.post(
        Uri.parse(AppConfig.grantCheckInPermissionUrl),
        headers: { 'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json' },
        body: json.encode({ 'targetUid': _selectedUserUid, 'global': global, 'eventId': _eventIdController.text.trim().isEmpty ? null : _eventIdController.text.trim() }),
      );
      if (resp.statusCode == 200) await _loadPermissions();
    } catch (_) {} finally { if (mounted) setState(() { _loading = false; }); }
  }

  Future<void> _revoke({required bool global, required String uid}) async {
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) return;
      final idToken = await user.getIdToken();
      setState(() { _loading = true; });
      final resp = await http.post(
        Uri.parse(AppConfig.revokeCheckInPermissionUrl),
        headers: { 'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json' },
        body: json.encode({ 'targetUid': uid, 'global': global, 'eventId': _eventIdController.text.trim().isEmpty ? null : _eventIdController.text.trim() }),
      );
      if (resp.statusCode == 200) await _loadPermissions();
    } catch (_) {} finally { if (mounted) setState(() { _loading = false; }); }
  }

  Future<void> _loadUsers({String q = ''}) async {
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) return;
      final idToken = await user.getIdToken();
      final uri = Uri.parse(AppConfig.listUsersBasicUrl + (q.isNotEmpty ? '?q=${Uri.encodeQueryComponent(q)}' : ''));
      final resp = await http.get(uri, headers: { 'Authorization': 'Bearer $idToken' });
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true) {
          setState(() { _users = body['users'] ?? []; });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadActiveEvents() async {
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) return;
      final idToken = await user.getIdToken();
      final resp = await http.get(
        Uri.parse(AppConfig.getEventsUrl),
        headers: { 'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json' },
      );
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true) {
          final eventsList = List<Map<String, dynamic>>.from(body['events'] as List);
          final now = DateTime.now();
          bool isOngoingOrFuture(Map<String, dynamic> e) {
            final endRaw = (e['endDate'] ?? '').toString();
            try {
              if (endRaw.isEmpty) return false;
              final end = DateTime.parse(endRaw);
              return !end.isBefore(now);
            } catch (_) {
              return false;
            }
          }
          final active = eventsList.where((e) => (e['registrationActivated'] == true) && isOngoingOrFuture(e)).toList();
          _activeEvents = active.map<Map<String, String>>((e) => {
            'id': (e['id'] ?? '').toString(),
            'label': '${(e['registrationDetails']?['eventName']) ?? e['typeName'] ?? e['type'] ?? 'Event'} • ${e['startDate'] ?? ''}',
          }).toList();
          _activeEvents.sort((a, b) => (a['label'] ?? '').compareTo(b['label'] ?? ''));
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text('Manage Permissions', style: TextStyle(color: Colors.amber)),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User dropdown by email
            FutureBuilder(
              future: _users.isEmpty ? _loadUsers() : Future.value(),
              builder: (context, snapshot) {
                return DropdownButtonFormField<String>(
                  initialValue: _selectedUserUid,
                  items: _users.map<DropdownMenuItem<String>>((u) {
                    final email = (u['email'] ?? u['uid'] ?? '').toString();
                    return DropdownMenuItem<String>(
                      value: u['uid'],
                      child: Text(email, style: TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() { _selectedUserUid = v; }),
                  dropdownColor: Colors.grey[900],
                  decoration: InputDecoration(hintText: 'Select user by email', hintStyle: TextStyle(color: Colors.grey)),
                );
              },
            ),
            SizedBox(height: 8),
            // Permission type dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedPermission,
              items: const [
                DropdownMenuItem(value: 'single_event_checkin', child: Text('Single Event Check-In')),
                DropdownMenuItem(value: 'all_event_checkin', child: Text('All Event Check-In')),
              ],
              onChanged: (v) => setState(() { _selectedPermission = v ?? 'single_event_checkin'; }),
              dropdownColor: Colors.grey[900],
              decoration: InputDecoration(hintText: 'Select permission', hintStyle: TextStyle(color: Colors.grey)),
            ),
            SizedBox(height: 8),
            if (_selectedPermission == 'single_event_checkin') ...[
              FutureBuilder(
                future: _activeEvents.isEmpty ? _loadActiveEvents() : Future.value(),
                builder: (context, snapshot) {
                  return DropdownButtonFormField<String>(
                    initialValue: _eventIdController.text.isNotEmpty ? _eventIdController.text : null,
                    items: _activeEvents.map((e) => DropdownMenuItem<String>(
                      value: e['id'], child: Text(e['label'] ?? 'Event', style: TextStyle(color: Colors.white))
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _eventIdController.text = v ?? ''; });
                      _loadPermissions();
                    },
                    dropdownColor: Colors.grey[900],
                    decoration: InputDecoration(hintText: 'Select active event', hintStyle: TextStyle(color: Colors.grey)),
                  );
                },
              ),
            ],
            SizedBox(height: 12),
            Row(children: [
              ElevatedButton(onPressed: _loading || _selectedUserUid == null ? null : () => _grant(global: _selectedPermission == 'all_event_checkin'), child: Text('Grant')),
              SizedBox(width: 8),
              ElevatedButton(onPressed: _loading || _selectedUserUid == null ? null : () => _revoke(global: _selectedPermission == 'all_event_checkin', uid: _selectedUserUid ?? ''), child: Text('Revoke')),
              SizedBox(width: 8),
              OutlinedButton(onPressed: _loading ? null : _loadPermissions, child: Text('Refresh', style: TextStyle(color: Colors.amber))),
            ]),
            SizedBox(height: 16),
            if (_loading) LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Global Check-in Access', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Container(
              constraints: BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                itemCount: _global.length,
                itemBuilder: (_, i) {
                  final u = _global[i];
                  return ListTile(
                    dense: true,
                    title: Text(u['uid'] ?? '', style: TextStyle(color: Colors.white)),
                    trailing: IconButton(icon: Icon(Icons.remove_circle, color: Colors.red), onPressed: _loading ? null : () => _revoke(global: true, uid: u['uid'])),
                  );
                },
              ),
            ),
            SizedBox(height: 12),
            Text('Users with Permissions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Container(
              constraints: BoxConstraints(maxHeight: 220),
              child: Builder(builder: (context) {
                // Build combined set of uids
                final Set<String> uids = {};
                for (final g in _global) { final uid = (g['uid'] ?? '').toString(); if (uid.isNotEmpty) uids.add(uid); }
                for (final e in _eventMembers) { final uid = (e['uid'] ?? '').toString(); if (uid.isNotEmpty) uids.add(uid); }
                final List<String> combined = uids.toList()..sort();
                String? emailFor(String uid) {
                  final match = _users.firstWhere((u) => (u['uid'] ?? '') == uid, orElse: () => {});
                  final email = (match is Map && match['email'] != null) ? match['email'].toString() : null;
                  return email;
                }
                bool hasGlobal(String uid) => _global.any((g) => (g['uid'] ?? '') == uid);
                bool hasEvent(String uid) => _eventMembers.any((g) => (g['uid'] ?? '') == uid);
                String eventLabelFor(String eventId) {
                  final m = _activeEvents.firstWhere((e) => (e['id'] ?? '') == eventId, orElse: () => {'label': ''});
                  return (m['label'] ?? '').toString();
                }
                final currentEventId = _eventIdController.text;
                final currentEventLabel = currentEventId.isNotEmpty ? eventLabelFor(currentEventId) : '';
                return ListView.builder(
                  itemCount: combined.length,
                  itemBuilder: (_, i) {
                    final uid = combined[i];
                    final email = emailFor(uid) ?? uid;
                    final List<String> perms = [];
                    if (hasGlobal(uid)) perms.add('All Event Check-In');
                    if (hasEvent(uid)) perms.add(currentEventLabel.isNotEmpty ? 'Single Event Check-In • $currentEventLabel' : 'Single Event Check-In');
                    return ListTile(
                      dense: true,
                      title: Text(email, style: TextStyle(color: Colors.white)),
                      subtitle: Text(perms.join(', '), style: TextStyle(color: Colors.grey)),
                      trailing: Wrap(spacing: 8, children: [
                        if (hasGlobal(uid)) OutlinedButton(
                          onPressed: _loading ? null : () => _revoke(global: true, uid: uid),
                          child: Text('Revoke Global'),
                        ),
                        if (hasEvent(uid)) OutlinedButton(
                          onPressed: _loading ? null : () => _revoke(global: false, uid: uid),
                          child: Text('Revoke Event'),
                        ),
                      ]),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close', style: TextStyle(color: Colors.amber)))
      ],
    );
  }
}

class _ImpersonateDialog extends StatefulWidget {
  @override
  State<_ImpersonateDialog> createState() => _ImpersonateDialogState();
}

class _ImpersonateDialogState extends State<_ImpersonateDialog> {
  List<dynamic> _users = [];
  String? _selectedUid;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers({String q = ''}) async {
    setState(() { _loading = true; });
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) return;
      final idToken = await user.getIdToken();
      final uri = Uri.parse(AppConfig.listUsersBasicUrl + (q.isNotEmpty ? '?q=${Uri.encodeQueryComponent(q)}' : ''));
      final resp = await http.get(uri, headers: { 'Authorization': 'Bearer $idToken' });
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true) {
          setState(() { 
            _users = body['users'] ?? []; 
            _loading = false;
          });
        } else {
          setState(() { _loading = false; });
        }
      } else {
        setState(() { _loading = false; });
      }
    } catch (_) {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text('Impersonate User', style: TextStyle(color: Colors.amber)),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) ...[
              Row(
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
                  Text('Loading users...', style: TextStyle(color: Colors.grey)),
                ],
              ),
              SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              initialValue: _selectedUid,
              items: _users.map<DropdownMenuItem<String>>((u) {
                final email = (u['email'] ?? u['uid'] ?? '').toString();
                final charNum = (u['characterNumber'] ?? '').toString();
                return DropdownMenuItem<String>(
                  value: u['uid'],
                  child: Text((charNum.isNotEmpty ? '$charNum • ' : '') + email, style: TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: _loading ? null : (v) => setState(() { _selectedUid = v; }),
              dropdownColor: Colors.grey[900],
              decoration: InputDecoration(
                hintText: _loading ? 'Loading users...' : 'Select user by email', 
                hintStyle: TextStyle(color: Colors.grey)
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: (_selectedUid == null || _loading) ? null : () {
            final match = _users.firstWhere((u) => (u['uid'] ?? '') == _selectedUid, orElse: () => {});
            final email = (match is Map && match['email'] != null) ? match['email'].toString() : null;
            print('🎭 Starting impersonation for UID: $_selectedUid, Email: $email');
            ImpersonationService.start(uid: _selectedUid!, email: email);
            print('🎭 ImpersonationService.isImpersonating: ${ImpersonationService.isImpersonating}');
            Navigator.of(context).pop();
            // Navigate back to home page to trigger character refresh
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          },
          child: Text('Impersonate'),
        ),
      ],
    );
  }
}

class _CreateNPCDialog extends StatefulWidget {
  @override
  State<_CreateNPCDialog> createState() => _CreateNPCDialogState();
}

class _CreateNPCDialogState extends State<_CreateNPCDialog> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedType = 'Cultivator';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text('Create NPC', style: TextStyle(color: Colors.amber)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'NPC Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('Type:', style: TextStyle(color: Colors.white, fontSize: 16)),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('Cultivator', style: TextStyle(color: Colors.white)),
                    value: 'Cultivator',
                    groupValue: _selectedType,
                    onChanged: (value) => setState(() => _selectedType = value!),
                    activeColor: Colors.amber,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('Monster', style: TextStyle(color: Colors.white)),
                    value: 'Monster',
                    groupValue: _selectedType,
                    onChanged: (value) => setState(() => _selectedType = value!),
                    activeColor: Colors.amber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createNPC,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: _isLoading 
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
                )
              : Text('Create', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Future<void> _createNPC() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a name for the NPC')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      
      // Create the NPC document in Firestore
      final response = await http.post(
        Uri.parse(AppConfig.createNPCUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'name': name,
          'type': _selectedType,
        }),
      );

                  if (response.statusCode == 200) {
                    final responseData = json.decode(response.body);
                    if (responseData['ok'] == true) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ NPC "$name" created successfully as $_selectedType'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      // Clear cache so it will refresh next time
                      await NPCCacheService.clearCache();
                    } else {
                      throw Exception(responseData['error'] ?? 'Failed to create NPC');
                    }
                  } else {
                    throw Exception('HTTP ${response.statusCode}: ${response.body}');
                  }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error creating NPC: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _ListNPCsDialog extends StatefulWidget {
  @override
  State<_ListNPCsDialog> createState() => _ListNPCsDialogState();
}

class _ListNPCsDialogState extends State<_ListNPCsDialog> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _cultivators = [];
  List<Map<String, dynamic>> _monsters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNPCs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNPCs() async {
    try {
      // Use cache service to get NPCs
      final npcsData = await NPCCacheService.getNPCs();
      
      if (mounted && npcsData != null) {
        setState(() {
          _cultivators = List<Map<String, dynamic>>.from(npcsData['cultivators'] ?? []);
          _monsters = List<Map<String, dynamic>>.from(npcsData['monsters'] ?? []);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error loading NPCs: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text('NPCs', style: TextStyle(color: Colors.amber)),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.amber,
              tabs: [
                Tab(
                  icon: Icon(Icons.person),
                  text: 'Cultivators (${_cultivators.length})',
                ),
                Tab(
                  icon: Icon(Icons.pets),
                  text: 'Monsters (${_monsters.length})',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildNPCList(_cultivators, 'Cultivator'),
                  _buildNPCList(_monsters, 'Monster'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: Colors.amber)),
        ),
      ],
    );
  }

  Widget _buildNPCList(List<Map<String, dynamic>> npcs, String type) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 16),
            Text('Loading ${type.toLowerCase()}s...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (npcs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'No ${type.toLowerCase()}s found',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: npcs.length,
      itemBuilder: (context, index) {
        final npc = npcs[index];
        final name = npc['name'] ?? 'Unknown';
        final createdAt = npc['createdAt'];
        final createdBy = npc['createdBy'] ?? 'Unknown';

        return Card(
          color: Colors.grey[800],
          margin: EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(
              type == 'Cultivator' ? Icons.person : Icons.pets,
              color: type == 'Cultivator' ? Colors.blue : Colors.red,
            ),
            title: Text(
              name,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Created by: $createdBy',
              style: TextStyle(color: Colors.grey),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (createdAt != null)
                  Text(
                    'Created: ${_formatDate(createdAt)}',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.edit, color: Colors.amber, size: 20),
                  onPressed: () => _editNPC(npc, type),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _deleteNPC(npc, type),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(dynamic timestamp) {
    try {
      if (timestamp is Map && timestamp['_seconds'] != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp['_seconds'] * 1000);
        return '${date.day}/${date.month}/${date.year}';
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _editNPC(Map<String, dynamic> npc, String type) async {
    final nameController = TextEditingController(text: npc['name']);
    String selectedType = type;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Edit NPC', style: TextStyle(color: Colors.amber)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'NPC Name',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.amber),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text('Type:', style: TextStyle(color: Colors.white, fontSize: 16)),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('Cultivator', style: TextStyle(color: Colors.white)),
                        value: 'Cultivator',
                        groupValue: selectedType,
                        onChanged: (value) => setState(() => selectedType = value!),
                        activeColor: Colors.amber,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('Monster', style: TextStyle(color: Colors.white)),
                        value: 'Monster',
                        groupValue: selectedType,
                        onChanged: (value) => setState(() => selectedType = value!),
                        activeColor: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a name for the NPC')),
                  );
                  return;
                }

                setState(() => isLoading = true);

                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) throw Exception('User not authenticated');

                  final idToken = await user.getIdToken();
                  
                  final response = await http.post(
                    Uri.parse(AppConfig.editNPCUrl),
                    headers: {
                      'Authorization': 'Bearer $idToken',
                      'Content-Type': 'application/json',
                    },
                    body: json.encode({
                      'id': npc['id'],
                      'name': name,
                      'type': selectedType,
                    }),
                  );

                  if (response.statusCode == 200) {
                    final responseData = json.decode(response.body);
                    if (responseData['ok'] == true) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ NPC "$name" updated successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      // Clear cache and reload
                      await NPCCacheService.clearCache();
                      _loadNPCs();
                    } else {
                      throw Exception(responseData['error'] ?? 'Failed to update NPC');
                    }
                  } else {
                    throw Exception('HTTP ${response.statusCode}: ${response.body}');
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error updating NPC: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  if (mounted) setState(() => isLoading = false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: isLoading 
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
                    )
                  : Text('Update', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteNPC(Map<String, dynamic> npc, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Delete NPC', style: TextStyle(color: Colors.red)),
        content: Text(
          'Are you sure you want to delete "${npc['name']}"? This action cannot be undone.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final idToken = await user.getIdToken();
        
        final response = await http.post(
          Uri.parse(AppConfig.deleteNPCUrl),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'id': npc['id'],
            'type': type,
          }),
        );

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['ok'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ NPC "${npc['name']}" deleted successfully'),
                backgroundColor: Colors.green,
              ),
            );
            // Clear cache and reload
            await NPCCacheService.clearCache();
            _loadNPCs();
          } else {
            throw Exception(responseData['error'] ?? 'Failed to delete NPC');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error deleting NPC: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
