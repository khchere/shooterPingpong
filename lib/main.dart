import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_scaffold.dart';
import 'screens/player_select_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '슈터탁구본부',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
        ),
        useMaterial3: true,
      ),
      home: const _EntryGate(),
    );
  }
}

class _EntryGate extends StatefulWidget {
  const _EntryGate();

  @override
  State<_EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<_EntryGate> {
  bool _checked = false;
  bool _hasPlayer = false;

  @override
  void initState() {
    super.initState();
    _checkSavedPlayer();
  }

  Future<void> _checkSavedPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('selected_player');
    setState(() {
      _hasPlayer = name != null && name.isNotEmpty;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    return _hasPlayer ? const MainScaffold() : const PlayerSelectScreen();
  }
}
