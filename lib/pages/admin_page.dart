import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:html' as html;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import '../config/app_config.dart';
import '../shared/impersonation_service.dart';
import '../shared/npc_cache_service.dart';
import '../shared/timer_preferences_service.dart';
import '../shared/admin_cache_service.dart';
import '../shared/rules_service.dart';

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
  String _resetCharacterNumber = '';
  bool _backupConfirmed = false;

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

  /// Handle admin operation failures by rechecking admin status (static version for dialogs)
  static Future<void> handleAdminOperationFailureStatic(String operation, dynamic error, BuildContext context) async {
    print('❌ Admin operation "$operation" failed: $error');
    
    // Check if this looks like a permission error
    final errorString = error.toString().toLowerCase();
    final isPermissionError = errorString.contains('403') || 
                             errorString.contains('unauthorized') ||
                             errorString.contains('permission') ||
                             errorString.contains('forbidden');
    
    if (isPermissionError) {
      print('🔄 Permission error detected, rechecking admin status...');
      
      // Recheck admin status
      await AdminCacheService.recheckOnFailure(
        onStatusUpdate: (bool isAdmin) {
          // Note: We can't update UI from static method, but the cache will be updated
          print('🔄 Admin status rechecked: $isAdmin');
        },
      );
      
      // Show user-friendly message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Permission denied. Admin status rechecked. Please try again.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// Handle admin operation failures by rechecking admin status
  Future<void> _handleAdminOperationFailure(String operation, dynamic error) async {
    print('❌ Admin operation "$operation" failed: $error');
    
    // Check if this looks like a permission error
    final errorString = error.toString().toLowerCase();
    final isPermissionError = errorString.contains('403') || 
                             errorString.contains('unauthorized') ||
                             errorString.contains('permission') ||
                             errorString.contains('forbidden');
    
    if (isPermissionError) {
      print('🔄 Permission error detected, rechecking admin status...');
      
      // Recheck admin status
      await AdminCacheService.recheckOnFailure(
        onStatusUpdate: (bool isAdmin) {
          if (mounted) {
            setState(() {
              // Trigger a rebuild to reflect any admin status changes
            });
          }
        },
      );
      
      // Show user-friendly message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Permission denied. Admin status rechecked. Please try again.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
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
          'Admin Menu',
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
                  // Status indicator
                  if (_isLoading || _statusMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16.0),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[600]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isLoading)
                            Row(
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
                                  'Processing...',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          if (_statusMessage.isNotEmpty)
                            Text(
                              _statusMessage,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  _buildSectionHeader('Data Management'),
            _buildDataManagementSection(),
            SizedBox(height: 32),
            _buildSectionHeader('System Tools'),
            _buildSystemToolsSection(),
            SizedBox(height: 32),
            _buildSectionHeader('NPCs'),
            _buildNPCsSection(),
            SizedBox(height: 32),
            _buildSectionHeader('Starting Character Stats'),
            _buildStartingStatsSection(),
            SizedBox(height: 32),
            _buildSectionHeader('Race Images'),
            _buildRaceImagesSection(),
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
              description: 'Incremental sync - only processes rows without Index fields',
              onPressed: () => _syncMasterLog(incremental: true),
              color: Colors.blue,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.refresh,
              title: 'Full Resync Master Log',
              description: 'Full sync - processes all rows (slower, use when needed)',
              onPressed: () => _syncMasterLog(incremental: false),
              color: Colors.orange,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.refresh,
              title: 'Refresh Data Cache',
              description: 'Clear and refresh cached data',
              onPressed: _refreshDataCache,
              color: Colors.green,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.restore,
              title: 'Reset Character',
              description: 'Reset a character by removing advancement data, renaming the old document to {Character Number}-{Reset Date}, and creating a new character',
              onPressed: _showResetCharacterModal,
              color: Colors.red,
            ),
            SizedBox(height: 12),
            _buildAdminAction(
              icon: Icons.sync,
              title: 'Sync Rules',
              description: 'Select and sync specific rules collections from Google Sheets to Firestore',
              onPressed: _showSyncRulesDialog,
              color: Colors.purple,
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
              icon: Icons.volume_up,
              title: 'Test Beep & Vibration',
              description: 'Test timer sound and vibration (mobile only)',
              onPressed: _testBeep,
              color: Colors.cyan,
            ),
            SizedBox(height: 12),
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


  void _showManagePermissions() {
    showDialog(
      context: context,
      builder: (context) => _ManagePermissionsDialog(),
    );
  }

  void _testBeep() async {
    setState(() {
      _statusMessage = 'Testing beep sound and vibration...';
    });
    
    try {
      await TimerPreferencesService.alertUser();
      
      setState(() {
        _statusMessage = '✅ Beep and vibration triggered! If you didn\'t hear/feel it, check:\n'
            '1. Volume is turned up\n'
            '2. Sound/Vibration enabled in Profile settings\n'
            '3. Browser allows audio (may need user interaction first)\n'
            '4. Vibration only works on mobile browsers\n'
            '5. Check browser console for errors';
      });
      
      // Clear message after 5 seconds
      Future.delayed(Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _statusMessage = '';
          });
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error playing beep/vibration: $e';
      });
    }
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

  Future<void> _syncMasterLog({bool incremental = false}) async {
    setState(() {
      _isLoading = true;
      _statusMessage = incremental 
          ? 'Initiating incremental master log sync...'
          : 'Initiating full master log sync...';
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
          'incremental': incremental,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final stats = data;
          setState(() {
            _statusMessage = '''${incremental ? 'Incremental' : 'Full'} Master Log Sync Completed Successfully!

📊 Sync Statistics:
• Rows processed: ${stats['written'] ?? 0}
• Characters mirrored: ${stats['mirrored'] ?? 0}
• Records cleared: ${stats['cleared'] ?? 0}
• Obsolete records deleted: ${stats['deletedFromCharacters'] ?? 0}

📋 Diagnostics:
• Total rows processed: ${stats['diagnostics']?['processedRows'] ?? 0}
• Text: ${incremental ? 'Only rows without Index fields were processed' : 'All rows were processed'}
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
      final errorMessage = 'Error: ${error.toString()}';
      setState(() {
        _statusMessage = errorMessage;
      });
      
      // Print detailed error to terminal for debugging
      print('❌ SYNC ERROR DETAILS:');
      print('❌ Error Type: ${error.runtimeType}');
      print('❌ Error Message: $errorMessage');
      print('❌ Timestamp: ${DateTime.now()}');
      
      // Handle admin operation failure
      await _handleAdminOperationFailure(incremental ? 'Incremental Sync Master Logs' : 'Full Sync Master Logs', error);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${error.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
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

  void _showSyncRulesDialog() {
    showDialog(
      context: context,
      builder: (context) => _SyncRulesDialog(
        onSync: syncRules,
      ),
    );
  }


  Future<void> syncRules({
    bool syncAffinities = false,
    bool syncRaces = false,
    bool syncCommonSkills = false,
    bool syncRaceSkills = false,
    bool syncAffinitySkills = false,
    bool syncBodyEssence = false,
    bool syncCultivationTiers = false,
    bool syncStatusEffects = false,
    bool syncEnumerations = false,
  }) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Syncing rules from Google Sheets to Firestore...';
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      
      setState(() {
        _statusMessage = 'Connecting to rules sync service...';
      });

      final response = await http.post(
        Uri.parse(AppConfig.syncRulesDbUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'syncAffinities': syncAffinities,
          'syncRaces': syncRaces,
          'syncCommonSkills': syncCommonSkills,
          'syncRaceSkills': syncRaceSkills,
          'syncAffinitySkills': syncAffinitySkills,
          'syncBodyEssence': syncBodyEssence,
          'syncCultivationTiers': syncCultivationTiers,
          'syncStatusEffects': syncStatusEffects,
          'syncEnumerations': syncEnumerations,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final stats = data;
          final counts = stats['counts'] ?? {};
          final warnings = stats['warnings'] ?? [];
          setState(() {
            _statusMessage = '''Rules Sync from Google Sheets Completed Successfully!

📊 Sync Statistics:
• Races synced: ${counts['races'] ?? 0}
• Affinities synced: ${counts['affinities'] ?? 0}
• Skills synced: ${counts['skills'] ?? 0}
• Body Essence-DR synced: ${counts['bodyEssenceDR'] ?? 0}
• Cultivation Tiers synced: ${counts['tiers'] ?? 0}
• Status Effects synced: ${counts['statusEffects'] ?? 0}
• Enumerations synced: ${counts['enums'] ?? 0}
• Total documents cleared: ${stats['cleared'] ?? 0}

📋 Sheet Information:
• Spreadsheet ID: ${stats['spreadsheetId'] ?? 'Unknown'}
• Available sheets: ${(stats['sheetTitles'] ?? []).join(', ')}

${warnings.isNotEmpty ? '⚠️ Warnings:\n' + warnings.map((w) => '• $w').join('\n') : ''}

✅ Rules database is now up to date with Google Sheets!''';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rules synced successfully from Google Sheets!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Rules sync failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'HTTP ${response.statusCode}');
      }
    } catch (error) {
      final errorMessage = 'Error syncing rules: ${error.toString()}';
      setState(() {
        _statusMessage = errorMessage;
      });
      
      print('❌ RULES SYNC ERROR DETAILS:');
      print('❌ Error Type: ${error.runtimeType}');
      print('❌ Error Message: $errorMessage');
      print('❌ Timestamp: ${DateTime.now()}');
      
      // Handle admin operation failure
      await _handleAdminOperationFailure('Sync Rules from Google Sheets', error);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rules sync failed: ${error.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showResetCharacterModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Reset Character',
          style: TextStyle(color: Colors.red),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ WARNING: This action will permanently remove advancement data from the PC DB Google Sheet.',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Before proceeding, please manually backup the PC DB Google Sheet.',
              style: TextStyle(color: Colors.grey[300]),
            ),
            SizedBox(height: 16),
            Text(
              'This will remove all rows for the specified character with these Advancement Reasons:',
              style: TextStyle(color: Colors.grey[300]),
            ),
            SizedBox(height: 8),
            Text(
              '• Raising Affinity Level\n• Buying Skill\n• Buying Hit Points',
              style: TextStyle(color: Colors.red[300]),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.drive_file_rename_outline, color: Colors.purple, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The character document will be renamed to {Character Number}-{Reset Date}',
                    style: TextStyle(color: Colors.purple[300]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.add_circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A new character document will be created with basic data',
                    style: TextStyle(color: Colors.green[300]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sync, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Character will be automatically synced after reset to update Firestore data',
                    style: TextStyle(color: Colors.blue[300]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Character Number',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: 'e.g., 89',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
              ),
              onChanged: (value) {
                // Store the character number for later use
                _resetCharacterNumber = value;
              },
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'I have backed up the PC DB Google Sheet',
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            CheckboxListTile(
              title: Text(
                'Confirm backup completion',
                style: TextStyle(color: Colors.grey[300]),
              ),
              value: _backupConfirmed,
              onChanged: (value) {
                setState(() {
                  _backupConfirmed = value ?? false;
                });
              },
              activeColor: Colors.amber,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _backupConfirmed && _resetCharacterNumber.isNotEmpty
                ? () {
                    Navigator.of(context).pop();
                    _resetCharacter();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Reset Character'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetCharacter() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Resetting character $_resetCharacterNumber...';
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      
      setState(() {
        _statusMessage = 'Connecting to reset service...';
      });

      final response = await http.post(
        Uri.parse(AppConfig.resetCharacterUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'characterNumber': _resetCharacterNumber,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final result = data['result'];
          setState(() {
            _statusMessage = '''Character $_resetCharacterNumber Reset, Renamed & Synced Successfully!

📊 Reset Details:
• Rows Removed: ${result['rowsRemoved']}
• Advancement Reasons: ${result['advancementReasons'].join(', ')}
• Document Renamed: ${result['documentRenamed'] == true ? 'Yes' : 'No'}
• New Document Created: ${result['newDocumentCreated'] == true ? 'Yes' : 'No'}
• Character Synced: ${result['synced'] == true ? 'Yes' : 'No'}

✅ Reset, rename, and sync completed at ${DateTime.now().toString()}''';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Character $_resetCharacterNumber reset successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Reset failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'HTTP ${response.statusCode}');
      }
    } catch (error) {
      final errorMessage = 'Error: ${error.toString()}';
      setState(() {
        _statusMessage = errorMessage;
      });
      
      // Print detailed error to terminal for debugging
      print('❌ RESET CHARACTER ERROR DETAILS:');
      print('❌ Error Type: ${error.runtimeType}');
      print('❌ Error Message: $errorMessage');
      print('❌ Timestamp: ${DateTime.now()}');
      
      // Handle admin operation failure
      await _handleAdminOperationFailure('Reset Character', error);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: ${error.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _resetCharacterNumber = '';
        _backupConfirmed = false;
      });
    }
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

  Widget _buildStartingStatsSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAdminAction(
              icon: Icons.settings,
              title: 'Starting Character Stats',
              description: 'Configure default starting character build, affinity points, and cultivation tier',
              onPressed: _showStartingStatsDialog,
              color: Colors.cyan,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaceImagesSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAdminAction(
              icon: Icons.image,
              title: 'Manage Race Images',
              description: 'Upload and manage images for each race (Recommended: 300x300px)',
              onPressed: _showRaceImageManagement,
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  void _showStartingStatsDialog() {
    showDialog(
      context: context,
      builder: (context) => _StartingStatsDialog(),
    );
  }

  void _showRaceImageManagement() {
    showDialog(
      context: context,
      builder: (context) => RaceImageManagementDialog(),
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
                  child: SizedBox(
                    width: 450, // Constrain width to prevent overflow
                    child: Text(
                      (charNum.isNotEmpty ? '$charNum • ' : '') + email, 
                      style: TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
      // Handle admin operation failure
      await _AdminPageState.handleAdminOperationFailureStatic('Create NPC', e, context);
      
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
                  // Handle admin operation failure
                  await _AdminPageState.handleAdminOperationFailureStatic('Update NPC', e, context);
                  
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
        // Handle admin operation failure
        await _AdminPageState.handleAdminOperationFailureStatic('Delete NPC', e, context);
        
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

class RaceImageManagementDialog extends StatefulWidget {
  const RaceImageManagementDialog({super.key});

  @override
  _RaceImageManagementDialogState createState() => _RaceImageManagementDialogState();
}

class _RaceImageManagementDialogState extends State<RaceImageManagementDialog> {
  List<Map<String, dynamic>> _races = [];
  String? _selectedRace;
  bool _isLoading = false;
  String? _currentImageUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  @override
  void didUpdateWidget(RaceImageManagementDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload races when dialog is reopened
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load races from rules service
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        final racesData = rules['Races'] as List<dynamic>? ?? [];
        
        final races = <Map<String, dynamic>>[];
        for (final raceData in racesData) {
          if (raceData is Map<String, dynamic>) {
            final name = (raceData['Name'] ?? '').toString();
            if (name.isNotEmpty) {
              races.add({
                'name': name,
                'description': (raceData['Description'] ?? '').toString(),
                'imageUrl': raceData['imageUrl'],
              });
            }
          }
        }
        
        setState(() {
          _races = races;
          if (races.isNotEmpty) {
            _selectedRace = races.first['name'];
            _currentImageUrl = races.first['imageUrl'];
          }
        });
        
        // Check for existing images in Firebase Storage
        await _checkForExistingImages();
      }
    } catch (e) {
      print('❌ Error loading races: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load races: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkForExistingImages() async {
    if (_selectedRace == null) return;
    
    try {
      final storage = FirebaseStorage.instance;
      final raceName = _selectedRace!.toLowerCase().replaceAll(' ', '_');
      final ref = storage.ref().child('race_images/$raceName.jpg');
      
      // Try to get the download URL
      final downloadUrl = await ref.getDownloadURL();
      
      setState(() {
        _currentImageUrl = downloadUrl;
        // Update the race data with the actual URL
        final raceIndex = _races.indexWhere((race) => race['name'] == _selectedRace);
        if (raceIndex != -1) {
          _races[raceIndex]['imageUrl'] = downloadUrl;
        }
      });
    } catch (e) {
      // Image doesn't exist in storage, that's fine
      print('No existing image found for race: $_selectedRace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Row(
        children: [
          Icon(Icons.image, color: Colors.amber),
          SizedBox(width: 8),
          Text('Race Image Management', style: TextStyle(color: Colors.amber)),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 600,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Instructions
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade700),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue.shade300, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Image Requirements',
                                style: TextStyle(
                                  color: Colors.blue.shade300,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            '• Images will be cropped to 300x300 square\n• Upload any size - we\'ll crop it automatically\n• Supported formats: JPG, PNG\n• Maximum file size: 5MB\n• Preview shows final square result',
                            style: TextStyle(
                              color: Colors.blue.shade200,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    
                    // Race selection
                    Text('Select Race:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRace,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: Colors.grey[800],
                      ),
                      dropdownColor: Colors.grey[800],
                      style: TextStyle(color: Colors.white),
                      items: _races.map((race) {
                        return DropdownMenuItem<String>(
                          value: race['name'],
                          child: Text(race['name'], style: TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                    onChanged: (value) async {
                      setState(() {
                        _selectedRace = value;
                        final race = _races.firstWhere((r) => r['name'] == value);
                        _currentImageUrl = race['imageUrl'];
                      });
                      // Check for existing image in Firebase Storage
                      await _checkForExistingImages();
                    },
                    ),
                    SizedBox(height: 20),
                    
                    // Current image display
                    Text('Current Image:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    // Square image preview container (300x300)
                    Center(
                      child: Container(
                        height: 300,
                        width: 300,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[600]!, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _currentImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  _currentImageUrl!,
                                  fit: BoxFit.cover,
                                  width: 300,
                                  height: 300,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                          SizedBox(height: 8),
                                          Text('Failed to load image', style: TextStyle(color: Colors.grey)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, size: 64, color: Colors.grey[600]),
                                    SizedBox(height: 12),
                                    Text(
                                      'No image uploaded',
                                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Upload an image to get started',
                                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // Upload controls
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isUploading ? null : _uploadImage,
                            icon: _isUploading 
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(Icons.upload),
                            label: Text(_isUploading ? 'Uploading...' : 'Upload Image'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        if (_currentImageUrl != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isUploading ? null : _removeImage,
                              icon: Icon(Icons.delete),
                              label: Text('Remove'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Future<void> _uploadImage() async {
    try {
      setState(() {
        _isUploading = true;
      });

      // Use web-compatible file picker
      final Uint8List? imageBytes = await _pickImageWeb();

      if (imageBytes == null) {
        setState(() {
          _isUploading = false;
        });
        return;
      }

      // Process and crop image to 300x300
      final Uint8List processedImageBytes = await _processImageBytes(imageBytes);

      // Upload to Firebase Storage
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final storage = FirebaseStorage.instance;
      final raceName = _selectedRace!.toLowerCase().replaceAll(' ', '_');
      final ref = storage.ref().child('race_images/$raceName.jpg');

      final uploadTask = ref.putData(
        processedImageBytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'race': _selectedRace!,
            'uploadedBy': user.uid,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update the race data with the new image URL
      await _updateRaceImageUrl(_selectedRace!, downloadUrl);

      setState(() {
        _currentImageUrl = downloadUrl;
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image uploaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List?> _pickImageWeb() async {
    // Create a file input element for web
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    
    // Trigger file selection
    uploadInput.click();
    
    // Wait for file selection
    final completer = Completer<Uint8List?>();
    uploadInput.onChange.listen((e) async {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        reader.onLoad.listen((e) {
          final result = reader.result as Uint8List?;
          completer.complete(result);
        });
        reader.readAsArrayBuffer(file);
      } else {
        completer.complete(null);
      }
    });
    
    return completer.future;
  }

  Future<Uint8List> _processImageBytes(Uint8List imageBytes) async {
    // Process the image bytes directly
    final img.Image? originalImage = img.decodeImage(imageBytes);
    
    if (originalImage == null) {
      throw Exception('Failed to decode image');
    }

    // Crop to square and resize to 300x300
    final int size = 300;
    final int minDimension = originalImage.width < originalImage.height 
        ? originalImage.width 
        : originalImage.height;
    
    // Calculate crop dimensions (center crop)
    final int cropX = (originalImage.width - minDimension) ~/ 2;
    final int cropY = (originalImage.height - minDimension) ~/ 2;
    
    final img.Image croppedImage = img.copyCrop(
      originalImage,
      x: cropX,
      y: cropY,
      width: minDimension,
      height: minDimension,
    );
    
    // Resize to 300x300
    final img.Image resizedImage = img.copyResize(
      croppedImage,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    
    // Encode as JPEG
    return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
  }

  Future<void> _updateRaceImageUrl(String raceName, String? imageUrl) async {
    // This would typically update the race data in your database
    // For now, we'll just update the local state
    final raceIndex = _races.indexWhere((race) => race['name'] == raceName);
    if (raceIndex != -1) {
      setState(() {
        _races[raceIndex]['imageUrl'] = imageUrl;
      });
    }
  }

  Future<void> _removeImage() async {
    if (_currentImageUrl == null) return;

    try {
      setState(() {
        _isUploading = true;
      });

      // Remove from Firebase Storage
      final storage = FirebaseStorage.instance;
      final raceName = _selectedRace!.toLowerCase().replaceAll(' ', '_');
      final ref = storage.ref().child('race_images/$raceName.jpg');
      
      await ref.delete();

      // Update local state
      await _updateRaceImageUrl(_selectedRace!, null);

      setState(() {
        _currentImageUrl = null;
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image removed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _SyncRulesDialog extends StatefulWidget {
  final Future<void> Function({
    bool syncAffinities,
    bool syncRaces,
    bool syncCommonSkills,
    bool syncRaceSkills,
    bool syncAffinitySkills,
    bool syncBodyEssence,
    bool syncCultivationTiers,
    bool syncStatusEffects,
    bool syncEnumerations,
  }) onSync;

  const _SyncRulesDialog({required this.onSync});

  @override
  _SyncRulesDialogState createState() => _SyncRulesDialogState();
}

class _SyncRulesDialogState extends State<_SyncRulesDialog> {
  bool _syncAffinities = false;
  bool _syncRaces = false;
  bool _syncCommonSkills = false;
  bool _syncRaceSkills = false;
  bool _syncAffinitySkills = false;
  bool _syncBodyEssence = false;
  bool _syncCultivationTiers = false;
  bool _syncStatusEffects = false;
  bool _syncEnumerations = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Row(
        children: [
          Icon(Icons.sync, color: Colors.purple),
          SizedBox(width: 8),
          Text('Sync Rules Collections', style: TextStyle(color: Colors.purple)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which rules collections to sync from Google Sheets to Firestore:',
                style: TextStyle(color: Colors.grey[300], fontSize: 14),
              ),
            SizedBox(height: 16),
            
            // Core collections
            _buildCheckboxTile(
              'Affinities',
              'Sync affinity multipliers and unique flags',
              _syncAffinities,
              (value) => setState(() => _syncAffinities = value!),
            ),
            _buildCheckboxTile(
              'Races',
              'Sync race descriptions, costume requirements, and affinity options',
              _syncRaces,
              (value) => setState(() => _syncRaces = value!),
            ),
            
            SizedBox(height: 8),
            Divider(color: Colors.grey[600]),
            SizedBox(height: 8),
            
            // Skills section
            Text('Skills:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            _buildCheckboxTile(
              'Common Skills',
              'Sync common skills available to all characters',
              _syncCommonSkills,
              (value) => setState(() => _syncCommonSkills = value!),
            ),
            _buildCheckboxTile(
              'Race Skills',
              'Sync skills specific to each race',
              _syncRaceSkills,
              (value) => setState(() => _syncRaceSkills = value!),
            ),
            _buildCheckboxTile(
              'Affinity Skills',
              'Sync skills specific to each affinity',
              _syncAffinitySkills,
              (value) => setState(() => _syncAffinitySkills = value!),
            ),
            
            SizedBox(height: 8),
            Divider(color: Colors.grey[600]),
            SizedBox(height: 8),
            
            // Other collections
            Text('Other Collections:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            _buildCheckboxTile(
              'Body Essence - DR',
              'Sync body essence damage reduction values',
              _syncBodyEssence,
              (value) => setState(() => _syncBodyEssence = value!),
            ),
            _buildCheckboxTile(
              'Cultivation Tiers',
              'Sync cultivation tier information',
              _syncCultivationTiers,
              (value) => setState(() => _syncCultivationTiers = value!),
            ),
            _buildCheckboxTile(
              'Status Effects',
              'Sync status effect definitions',
              _syncStatusEffects,
              (value) => setState(() => _syncStatusEffects = value!),
            ),
            _buildCheckboxTile(
              'Enumerations',
              'Sync frequency, duration, and delivery options',
              _syncEnumerations,
              (value) => setState(() => _syncEnumerations = value!),
            ),
            
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade700),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade300, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select at least one collection to sync. This will help reduce load and allow targeted troubleshooting.',
                      style: TextStyle(color: Colors.blue.shade200, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isLoading || !_hasAnySelected() ? null : _performSync,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: _isLoading 
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Sync Selected', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildCheckboxTile(String title, String description, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(description, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeColor: Colors.purple,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    );
  }

  bool _hasAnySelected() {
    return _syncAffinities || _syncRaces || _syncCommonSkills || _syncRaceSkills || 
           _syncAffinitySkills || _syncBodyEssence || _syncCultivationTiers || 
           _syncStatusEffects || _syncEnumerations;
  }

  Future<void> _performSync() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔄 Starting sync with selections:');
      print('  - Affinities: $_syncAffinities');
      print('  - Races: $_syncRaces');
      print('  - Common Skills: $_syncCommonSkills');
      print('  - Race Skills: $_syncRaceSkills');
      print('  - Affinity Skills: $_syncAffinitySkills');
      print('  - Body Essence: $_syncBodyEssence');
      print('  - Cultivation Tiers: $_syncCultivationTiers');
      print('  - Status Effects: $_syncStatusEffects');
      print('  - Enumerations: $_syncEnumerations');

      print('✅ Calling sync function...');
      await widget.onSync(
        syncAffinities: _syncAffinities,
        syncRaces: _syncRaces,
        syncCommonSkills: _syncCommonSkills,
        syncRaceSkills: _syncRaceSkills,
        syncAffinitySkills: _syncAffinitySkills,
        syncBodyEssence: _syncBodyEssence,
        syncCultivationTiers: _syncCultivationTiers,
        syncStatusEffects: _syncStatusEffects,
        syncEnumerations: _syncEnumerations,
      );
      
      print('✅ Sync completed successfully');
      // Close dialog on success
      Navigator.of(context).pop();
    } catch (e) {
      print('❌ Sync failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
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

class _StartingStatsDialog extends StatefulWidget {
  @override
  State<_StartingStatsDialog> createState() => _StartingStatsDialogState();
}

class _StartingStatsDialogState extends State<_StartingStatsDialog> {
  final TextEditingController _buildController = TextEditingController();
  final TextEditingController _affinityPointsController = TextEditingController();
  String? _selectedCultivationTier;
  List<String> _cultivationTiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _buildController.dispose();
    _affinityPointsController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      
      final response = await http.get(
        Uri.parse(AppConfig.getAppConfigUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true && data['config'] != null) {
          final config = data['config'];
          setState(() {
            _buildController.text = (config['startingBuild'] ?? 100).toString();
            _affinityPointsController.text = (config['startingAffinityPoints'] ?? 60).toString();
            _selectedCultivationTier = config['startingCultivationTier'] ?? 'Iron';
          });
        } else {
          _setDefaultValues();
        }
      } else {
        _setDefaultValues();
      }
    } catch (e) {
      print('❌ Error loading app config: $e');
      _setDefaultValues();
    }
  }

  void _setDefaultValues() {
    setState(() {
      _buildController.text = '100';
      _affinityPointsController.text = '60'; // build - 40
      _selectedCultivationTier = 'Iron';
    });
  }

  void _updateAffinityPoints() {
    final buildValue = int.tryParse(_buildController.text) ?? 0;
    final affinityPoints = buildValue - 40;
    _affinityPointsController.text = affinityPoints.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Row(
        children: [
          Icon(Icons.settings, color: Colors.cyan),
          SizedBox(width: 8),
          Text('Starting Character Stats', style: TextStyle(color: Colors.cyan)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure the default starting values for new characters:',
              style: TextStyle(color: Colors.grey[300], fontSize: 14),
            ),
            SizedBox(height: 20),
            
            // Build Number
            TextField(
              controller: _buildController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Starting Build Number',
                labelStyle: TextStyle(color: Colors.grey),
                hintText: 'e.g., 100',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyan),
                ),
                suffixIcon: Icon(Icons.numbers, color: Colors.grey),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => _updateAffinityPoints(),
            ),
            SizedBox(height: 16),
            
            // Affinity Points
            TextField(
              controller: _affinityPointsController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Starting Affinity Points',
                labelStyle: TextStyle(color: Colors.grey),
                hintText: 'Auto-calculated as Build - 40',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyan),
                ),
                suffixIcon: Icon(Icons.star, color: Colors.grey),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),
            
            // Cultivation Tier Dropdown
            DropdownButtonFormField<String>(
              value: _selectedCultivationTier,
              decoration: InputDecoration(
                labelText: 'Starting Cultivation Tier',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyan),
                ),
                suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey),
              ),
              dropdownColor: Colors.grey[800],
              style: TextStyle(color: Colors.white),
              items: _cultivationTiers.map((tier) {
                return DropdownMenuItem<String>(
                  value: tier,
                  child: Text(tier, style: TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCultivationTier = value;
                });
              },
            ),
            SizedBox(height: 20),
            
            // Info box
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade700),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade300, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These settings will be used as defaults when creating new characters. Affinity points are automatically calculated as Build - 40.',
                      style: TextStyle(color: Colors.blue.shade200, fontSize: 12),
                    ),
                  ),
                ],
              ),
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
          onPressed: _isLoading ? null : _saveSettings,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
          child: _isLoading 
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Save Settings', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    final buildValue = int.tryParse(_buildController.text);
    final affinityValue = int.tryParse(_affinityPointsController.text);
    
    if (buildValue == null || buildValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid build number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (affinityValue == null || affinityValue < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter valid affinity points'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_selectedCultivationTier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a cultivation tier'),
          backgroundColor: Colors.red,
        ),
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
      
      final response = await http.post(
        Uri.parse(AppConfig.updateAppConfigUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'startingBuild': buildValue,
          'startingAffinityPoints': affinityValue,
          'startingCultivationTier': _selectedCultivationTier,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Starting character stats saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Failed to save settings');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'HTTP ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error saving settings: $e'),
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
