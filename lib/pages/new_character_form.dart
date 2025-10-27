import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../shared/rules_service.dart';

class NewCharacterForm extends StatefulWidget {
  const NewCharacterForm({super.key});

  @override
  State<NewCharacterForm> createState() => _NewCharacterFormState();
}

class _NewCharacterFormState extends State<NewCharacterForm> {
  int _currentStep = 0;
  final PageController _pageController = PageController();
  
  // Form data
  final TextEditingController _characterNameController = TextEditingController();
  final TextEditingController _playerNameController = TextEditingController();
  String? _selectedRace;
  String? _selectedFreeAffinity;
  
  // Data
  List<RaceInfo> _races = [];
  bool _isLoadingRaces = true;
  bool _isCreatingCharacter = false;
  
  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _loadRaces();
  }
  
  @override
  void dispose() {
    _characterNameController.dispose();
    _playerNameController.dispose();
    _pageController.dispose();
    super.dispose();
  }
  
  void _loadPlayerName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null) {
      _playerNameController.text = user!.displayName!;
    } else if (user?.email != null) {
      // Extract name from email if no display name
      final email = user!.email!;
      final name = email.split('@')[0];
      _playerNameController.text = name;
    }
  }
  
  Future<void> _loadRaces() async {
    try {
      setState(() {
        _isLoadingRaces = true;
      });
      
      // First try to load cached rules
      String? cachedRules = await RulesService.loadCachedRules();
      
      // If no cached rules, fetch them from Firestore
      if (cachedRules == null) {
        print('📥 No cached rules found, fetching from Firestore...');
        await RulesService.fetchAndCacheRules();
        cachedRules = await RulesService.loadCachedRules();
        
        if (cachedRules == null) {
          throw Exception('Failed to load rules from Firestore');
        }
      }
      
      final rules = json.decode(cachedRules);
      final racesData = rules['Races'] as List<dynamic>? ?? [];
      
      final races = <RaceInfo>[];
      for (final raceData in racesData) {
        if (raceData is Map<String, dynamic>) {
          final name = (raceData['Name'] ?? '').toString();
          if (name.isNotEmpty) {
            final affinityOptions = (raceData['AffinityOptions'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
            
            races.add(RaceInfo(
              name: name,
              description: (raceData['Description'] ?? '').toString(),
              affinityOptions: affinityOptions,
              imageUrl: (raceData['imageUrl'] as String?),
              requirements: (raceData['Costume Requirements'] ?? '').toString(),
              specialAbilities: (raceData['SpecialAbilities'] ?? '').toString(),
              notes: (raceData['Notes'] ?? '').toString(),
            ));
          }
        }
      }
      
      // Sort races alphabetically by name (case-insensitive)
      races.sort((a, b) => a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase()));
      
      setState(() {
        _races = races;
        _isLoadingRaces = false;
      });
      
      // Load race images from Firebase Storage
      await _loadRaceImages();
    } catch (e) {
      print('❌ Error loading races: $e');
      setState(() {
        _isLoadingRaces = false;
      });
      
      if (mounted) {
        String errorMessage = 'Failed to load race information';
        if (e.toString().contains('Failed to load rules from Firestore')) {
          errorMessage = 'Unable to connect to the rules database. Please check your internet connection and try again.';
        } else if (e.toString().contains('Rules not available')) {
          errorMessage = 'Rules data is not available. Please try again in a moment.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadRaces(),
            ),
          ),
        );
      }
    }
  }
  
  Future<void> _loadRaceImages() async {
    final storage = FirebaseStorage.instance;
    
    for (int i = 0; i < _races.length; i++) {
      try {
        final race = _races[i];
        final raceName = race.name.toLowerCase().replaceAll(' ', '_');
        final ref = storage.ref().child('race_images/$raceName.jpg');
        
        // Try to get the download URL
        final downloadUrl = await ref.getDownloadURL();
        
        // Update the race with the image URL
        setState(() {
          _races[i] = RaceInfo(
            name: race.name,
            description: race.description,
            affinityOptions: race.affinityOptions,
            imageUrl: downloadUrl,
            requirements: race.requirements,
            specialAbilities: race.specialAbilities,
            notes: race.notes,
          );
        });
      } catch (e) {
        // Image doesn't exist in storage, that's fine
        print('No image found for race: ${_races[i].name}');
      }
    }
  }
  
  void _nextStep() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
      
      // Auto-skip affinity selection if there's only one option
      if (_currentStep == 2 && _selectedRace != null) {
        final race = _races.firstWhere(
          (r) => r.name == _selectedRace,
          orElse: () => RaceInfo(name: '', description: '', affinityOptions: [], requirements: '', specialAbilities: '', notes: ''),
        );
        
        if (race.affinityOptions.length == 1) {
          // Auto-select the single affinity option and skip to creation
          _selectedFreeAffinity = race.affinityOptions.first;
          
          // Show brief message to user about auto-selection
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Auto-selected ${_selectedFreeAffinity} as the only available affinity'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.blue,
              ),
            );
          }
          
          _createCharacter();
          return;
        }
      }
      
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _characterNameController.text.trim().isNotEmpty &&
               _playerNameController.text.trim().isNotEmpty;
      case 1:
        return _selectedRace != null;
      case 2:
        if (_selectedRace == null) return false;
        final race = _races.firstWhere(
          (r) => r.name == _selectedRace,
          orElse: () => RaceInfo(name: '', description: '', affinityOptions: [], requirements: '', specialAbilities: '', notes: ''),
        );
        return race.affinityOptions.isEmpty || _selectedFreeAffinity != null;
      default:
        return false;
    }
  }
  
  Future<void> _createCharacter() async {
    if (!_canProceedFromStep(2)) return;
    
    setState(() {
      _isCreatingCharacter = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      
      final idToken = await user.getIdToken();
      
      final characterData = {
        'characterName': _characterNameController.text.trim(),
        'playerName': _playerNameController.text.trim(),
        'race': _selectedRace!,
        'freeAffinity': _selectedFreeAffinity,
      };
      
      final response = await http.post(
        Uri.parse(AppConfig.createCharacterUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(characterData),
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          // Character created successfully
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Character created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            
            // Navigate back to main app
            Navigator.of(context).pop(true);
          }
        } else {
          throw Exception(responseData['error'] ?? 'Failed to create character');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error creating character: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create character: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingCharacter = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Character'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator removed to avoid confusion with auto-skip
          
          // Step indicator removed to avoid confusion with auto-skip
          
          const SizedBox(height: 16),
          
          // Form content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicInfoStep(),
                _buildRaceSelectionStep(),
                _buildAffinitySelectionStep(),
              ],
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousStep,
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canProceedFromStep(_currentStep) 
                        ? (_currentStep == 2 ? _createCharacter : _nextStep)
                        : null,
                    child: _isCreatingCharacter
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_currentStep == 2 ? 'Create Character' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBasicInfoStep() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Basic Information',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us about your character',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          
          TextFormField(
            controller: _characterNameController,
            decoration: const InputDecoration(
              labelText: 'Character Name',
              hintText: 'Enter your character\'s name',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _playerNameController,
            decoration: const InputDecoration(
              labelText: 'Player Name',
              hintText: 'Enter your name',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {}),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRaceSelectionStep() {
    if (_isLoadingRaces) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Race',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a race for your character',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _races.length,
              itemBuilder: (context, index) {
                final race = _races[index];
                final isSelected = _selectedRace == race.name;
                
                return _buildRaceCard(race, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRaceCard(RaceInfo race, bool isSelected) {
    return GestureDetector(
      onTap: () => _showRaceDetails(race),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade600 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
          border: isSelected 
            ? Border.all(color: Colors.blue.shade400, width: 2)
            : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Race image (only show if available)
              if (race.imageUrl != null)
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      race.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        // Don't show placeholder on error, just return empty container
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              
              const SizedBox(height: 12),
              
              // Race name only
              Text(
                race.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // Tap to see details hint
              Text(
                'Tap to see details',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showRaceDetails(RaceInfo race) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // Race image (only show if available)
                    if (race.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          race.imageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            // Don't show placeholder on error, just return empty container
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    
                    const SizedBox(width: 16),
                    
                    // Race name
                    Expanded(
                      child: Text(
                        race.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Description
                      if (race.description.isNotEmpty) ...[
                        Text(
                          race.description,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 16),
                      ],
                      
                      // Costume Requirements
                      if (race.requirements.isNotEmpty) ...[
                        Text(
                          'Costume Requirements',
                          style: TextStyle(
                            color: Colors.blue.shade300,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          race.requirements,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 16),
                      ],
                      
                      // Special Abilities
                      if (race.specialAbilities.isNotEmpty) ...[
                        Text(
                          'Special Abilities',
                          style: TextStyle(
                            color: Colors.blue.shade300,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          race.specialAbilities,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 16),
                      ],
                      
                      // Notes
                      if (race.notes.isNotEmpty) ...[
                        Text(
                          'Notes',
                          style: TextStyle(
                            color: Colors.blue.shade300,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          race.notes,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Buttons
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedRace = race.name;
                          });
                          Navigator.of(context).pop();
                        },
                        child: Text(_selectedRace == race.name ? 'Selected' : 'Select'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAffinitySelectionStep() {
    if (_selectedRace == null) {
      return const Center(
        child: Text('Please select a race first'),
      );
    }
    
    final race = _races.firstWhere(
      (r) => r.name == _selectedRace,
      orElse: () => RaceInfo(name: '', description: '', affinityOptions: [], requirements: '', specialAbilities: '', notes: ''),
    );
    
    // If race has only one affinity option, skip this step
    if (race.affinityOptions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            Text(
              'Ready to Create Character',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your race has a single free affinity option.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Free Affinity',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select your free affinity for ${race.name}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: ListView.builder(
              itemCount: race.affinityOptions.length,
              itemBuilder: (context, index) {
                final affinity = race.affinityOptions[index];
                final isSelected = _selectedFreeAffinity == affinity;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
                      child: Icon(
                        Icons.star,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                    title: Text(
                      affinity,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.blue)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedFreeAffinity = affinity;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RaceInfo {
  final String name;
  final String description;
  final List<String> affinityOptions;
  final String? imageUrl;
  final String requirements;
  final String specialAbilities;
  final String notes;
  
  RaceInfo({
    required this.name,
    required this.description,
    required this.affinityOptions,
    this.imageUrl,
    required this.requirements,
    required this.specialAbilities,
    required this.notes,
  });
}
