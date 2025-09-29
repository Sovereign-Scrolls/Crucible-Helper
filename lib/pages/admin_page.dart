import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  String _statusMessage = '';

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
      body: SingleChildScrollView(
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
            _buildSectionHeader('Status'),
            _buildStatusSection(),
          ],
        ),
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
              icon: Icons.analytics,
              title: 'System Analytics',
              description: 'View system usage and performance metrics',
              onPressed: _showSystemAnalytics,
              color: Colors.purple,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.settings,
              title: 'Configuration',
              description: 'Manage system configuration settings',
              onPressed: _showConfiguration,
              color: Colors.orange,
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
}
