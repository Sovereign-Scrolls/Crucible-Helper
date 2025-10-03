import 'dart:async';
import 'package:flutter/material.dart';

enum TimerType { death, exhaustion, imprison }
enum TimerState { ready, running, paused, completed }
enum DeathStage { bleedingOut, unconscious, dead }

class TimerData {
  final TimerType type;
  TimerState state;
  int remainingSeconds;
  int totalSeconds;
  DeathStage? deathStage;
  Timer? timer;
  
  // For death timer - separate stage timers
  int stage1Seconds;
  int stage2Seconds;
  bool isStage1Active;

  TimerData({
    required this.type,
    this.state = TimerState.ready,
    required this.totalSeconds,
    this.deathStage,
  }) : remainingSeconds = totalSeconds,
       stage1Seconds = type == TimerType.death ? 60 : 0,  // 1 minute for stage 1
       stage2Seconds = type == TimerType.death ? 120 : 0, // 2 minutes for stage 2
       isStage1Active = type == TimerType.death;

  String get displayName {
    switch (type) {
      case TimerType.death:
        return 'Death Timer';
      case TimerType.exhaustion:
        return 'Exhaustion/1 minute';
      case TimerType.imprison:
        return 'Imprison';
    }
  }

  String get timeDisplay {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color get stateColor {
    switch (state) {
      case TimerState.ready:
        return Colors.green[400]!;
      case TimerState.running:
        if (type == TimerType.death) {
          if (deathStage == DeathStage.bleedingOut) return Colors.red[400]!;
          if (deathStage == DeathStage.unconscious) return Colors.purple[600]!;
          return Colors.grey[800]!; // dead
        }
        return type == TimerType.exhaustion ? Colors.orange[400]! : Colors.blue[400]!;
      case TimerState.paused:
        return Colors.yellow[600]!;
      case TimerState.completed:
        return Colors.grey[600]!;
    }
  }

  String get stateText {
    switch (state) {
      case TimerState.ready:
        return 'Ready';
      case TimerState.running:
        if (type == TimerType.death) {
          if (deathStage == DeathStage.bleedingOut) return 'Stage 1: Bleeding Out';
          if (deathStage == DeathStage.unconscious) return 'Stage 2: Unconscious/Dying';
          return 'Dead';
        }
        return 'Active';
      case TimerState.paused:
        return 'Paused';
      case TimerState.completed:
        return type == TimerType.death ? 'Dead' : 'Completed';
    }
  }
}

class DeathTimerPage extends StatefulWidget {
  const DeathTimerPage({super.key});

  @override
  _DeathTimerPageState createState() => _DeathTimerPageState();
}

class _DeathTimerPageState extends State<DeathTimerPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late Map<TimerType, TimerData> _timers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    _timers = {
      TimerType.death: TimerData(
        type: TimerType.death,
        totalSeconds: 180, // Total 3 minutes (not used for death timer)
        deathStage: DeathStage.bleedingOut,
      ),
      TimerType.exhaustion: TimerData(
        type: TimerType.exhaustion,
        totalSeconds: 60, // 1 minute
      ),
      TimerType.imprison: TimerData(
        type: TimerType.imprison,
        totalSeconds: 180, // 3 minutes
      ),
    };
    
    // Set death timer to start with Stage 1 (1 minute)
    _timers[TimerType.death]!.remainingSeconds = _timers[TimerType.death]!.stage1Seconds;
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var timer in _timers.values) {
      timer.timer?.cancel();
    }
    super.dispose();
  }

  void _startTimer(TimerType type) {
    final timerData = _timers[type]!;
    if (timerData.state == TimerState.running) return;

    setState(() {
      timerData.state = TimerState.running;
    });

    timerData.timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      setState(() {
        if (timerData.remainingSeconds > 0) {
          timerData.remainingSeconds--;
          
          // Handle death timer stage transitions
          if (type == TimerType.death) {
            if (timerData.isStage1Active) {
              // We're in Stage 1 (Bleeding Out)
              timerData.deathStage = DeathStage.bleedingOut;
              
              // When Stage 1 reaches 0, transition to Stage 2
              if (timerData.remainingSeconds == 0) {
                timerData.isStage1Active = false;
                timerData.remainingSeconds = timerData.stage2Seconds; // Start Stage 2 with 2 minutes
                timerData.deathStage = DeathStage.unconscious;
                print('🔄 Death timer: Stage 1 complete, starting Stage 2 (2:00)');
              }
            } else {
              // We're in Stage 2 (Unconscious/Dying)
              timerData.deathStage = DeathStage.unconscious;
              
              // When Stage 2 reaches 0, character is dead
              if (timerData.remainingSeconds == 0) {
                timerData.deathStage = DeathStage.dead;
                timerData.state = TimerState.completed;
                timer.cancel();
                print('💀 Death timer: Character is dead');
              }
            }
          }
        } else {
          // For non-death timers, just complete
          if (type != TimerType.death) {
            timer.cancel();
            timerData.state = TimerState.completed;
          }
        }
      });
    });
  }

  void _pauseTimer(TimerType type) {
    final timerData = _timers[type]!;
    timerData.timer?.cancel();
    setState(() {
      timerData.state = TimerState.paused;
    });
  }

  void _resetTimer(TimerType type) {
    final timerData = _timers[type]!;
    timerData.timer?.cancel();
    setState(() {
      if (type == TimerType.death) {
        // Reset death timer to Stage 1
        timerData.remainingSeconds = timerData.stage1Seconds; // 1 minute
        timerData.isStage1Active = true;
        timerData.deathStage = DeathStage.bleedingOut;
      } else {
        timerData.remainingSeconds = timerData.totalSeconds;
      }
      timerData.state = TimerState.ready;
    });
  }

  void _healCharacter() {
    final deathTimer = _timers[TimerType.death]!;
    deathTimer.timer?.cancel();
    setState(() {
      // Reset death timer to Stage 1
      deathTimer.remainingSeconds = deathTimer.stage1Seconds; // 1 minute
      deathTimer.isStage1Active = true;
      deathTimer.state = TimerState.ready;
      deathTimer.deathStage = DeathStage.bleedingOut;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Character healed! Death timer reset.'),
        backgroundColor: Colors.green[600],
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTimerTab(TimerType type) {
    final timerData = _timers[type]!;
    
    if (type == TimerType.death) {
      return _buildDeathTimerTab(timerData);
    } else {
      return _buildSimpleTimerTab(timerData);
    }
  }

  Widget _buildDeathTimerTab(TimerData timerData) {
    return Container(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Stage 1: Bleeding Out
            Expanded(
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: timerData.isStage1Active && timerData.state == TimerState.running
                      ? Colors.red[400]!.withOpacity(0.2)
                      : Colors.grey[900],
                  border: Border.all(
                    color: timerData.isStage1Active && timerData.state == TimerState.running
                        ? Colors.red[400]!
                        : Colors.grey[700]!,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bloodtype,
                            color: Colors.red[400],
                            size: 28,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Stage 1: Bleeding Out',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Text(
                        // Show current timer if this stage is active, otherwise show the stage's full duration
                        timerData.isStage1Active && timerData.state == TimerState.running
                            ? timerData.timeDisplay
                            : timerData.isStage1Active && timerData.state != TimerState.completed
                                ? timerData.timeDisplay  // Show current time if ready/paused
                                : '1:00', // Show full duration if not active or completed
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: timerData.isStage1Active && timerData.state == TimerState.running
                              ? Colors.red[400]
                              : Colors.grey[400],
                        ),
                      ),
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'This stage lasts 1 minute and any healing will bring the character back to playability at 1 essence.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[300],
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Stage 2: Unconscious/Dying
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: !timerData.isStage1Active && timerData.state == TimerState.running
                      ? Colors.purple[600]!.withOpacity(0.2)
                      : Colors.grey[900],
                  border: Border.all(
                    color: !timerData.isStage1Active && timerData.state == TimerState.running
                        ? Colors.purple[600]!
                        : Colors.grey[700]!,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.psychology_alt,
                            color: Colors.purple[400],
                            size: 28,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Stage 2: Unconscious/Dying',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Text(
                        // Show current timer if Stage 2 is active, otherwise show 2:00
                        !timerData.isStage1Active && timerData.state == TimerState.running
                            ? timerData.timeDisplay
                            : !timerData.isStage1Active && timerData.state != TimerState.ready
                                ? timerData.timeDisplay  // Show current time if paused or completed
                                : '2:00', // Show full duration when ready or Stage 1 is active
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: !timerData.isStage1Active && timerData.state == TimerState.running
                              ? Colors.purple[400]
                              : Colors.grey[400],
                        ),
                      ),
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'The character may only be healed through a Life Effect ability.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[300],
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: timerData.state == TimerState.ready || timerData.state == TimerState.paused
                      ? () => _startTimer(TimerType.death)
                      : null,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: timerData.state == TimerState.running
                      ? () => _pauseTimer(TimerType.death)
                      : null,
                  icon: Icon(Icons.pause),
                  label: Text('Pause'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _healCharacter(),
                  icon: Icon(Icons.healing),
                  label: Text('Heal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _resetTimer(TimerType.death),
                  icon: Icon(Icons.refresh),
                  label: Text('Reset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleTimerTab(TimerData timerData) {
    return Container(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: timerData.stateColor.withOpacity(0.2),
                border: Border.all(color: timerData.stateColor, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    timerData.type == TimerType.exhaustion ? Icons.battery_0_bar : Icons.lock,
                    size: 64,
                    color: timerData.stateColor,
                  ),
                  SizedBox(height: 20),
                  Text(
                    timerData.displayName,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    timerData.stateText,
                    style: TextStyle(
                      fontSize: 18,
                      color: timerData.stateColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    timerData.timeDisplay,
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: timerData.stateColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 40),
            
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: timerData.state == TimerState.ready || timerData.state == TimerState.paused
                      ? () => _startTimer(timerData.type)
                      : null,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: timerData.stateColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: timerData.state == TimerState.running
                      ? () => _pauseTimer(timerData.type)
                      : null,
                  icon: Icon(Icons.pause),
                  label: Text('Pause'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _resetTimer(timerData.type),
                  icon: Icon(Icons.refresh),
                  label: Text('Reset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Timers',
          style: TextStyle(
            color: Colors.amber,
            fontFamily: 'Cinzel',
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.favorite, color: Colors.red[400]),
              text: 'Death',
            ),
            Tab(
              icon: Icon(Icons.battery_0_bar, color: Colors.orange[400]),
              text: 'Exhaustion/1 min',
            ),
            Tab(
              icon: Icon(Icons.lock, color: Colors.blue[400]),
              text: 'Imprison',
            ),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[400],
          indicatorColor: Colors.amber,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTimerTab(TimerType.death),
          _buildTimerTab(TimerType.exhaustion),
          _buildTimerTab(TimerType.imprison),
        ],
      ),
    );
  }
}