import 'dart:async';
import 'package:flutter/material.dart';

class DeathTimerPage extends StatefulWidget {
  const DeathTimerPage({super.key});

  @override
  _DeathTimerPageState createState() => _DeathTimerPageState();
}

class _DeathTimerPageState extends State<DeathTimerPage> {
  Timer? _timer;
  int _remainingSeconds = 180; // 3 minutes
  bool _isRunning = false;

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _isRunning = false;
        }
      });
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 180;
      _isRunning = false;
    });
  }

  void _heal() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 180;
      _isRunning = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Healed! Death count reset.'),
      duration: Duration(seconds: 2),
    ));
  }

  String _getStatusLabel() {
    if (_remainingSeconds > 120) return "Stage 1: Bleeding Out";
    if (_remainingSeconds > 0) return "Stage 2: Unconscious/Dying";
    return "Dead";
  }

  Color _getStatusColor() {
    if (_remainingSeconds > 120) return Colors.red;
    if (_remainingSeconds > 0) return Colors.purple;
    return Colors.grey;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getStatusColor(),
      appBar: AppBar(
        title: Text('Death Timer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getStatusLabel(),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 48),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startTimer,
              child: Text('Start Death Timer'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _heal,
              child: Text('Healed / Life Effect Used'),
            ),
            SizedBox(height: 10),
            TextButton(
              onPressed: _resetTimer,
              child: Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}


