import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'duo_screen.dart';
import 'chart_screen.dart';
import 'match_list_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final List<int> _tabKeys = [0, 0, 0, 0];

  Widget _buildScreen(int index) {
    final key = ValueKey('tab_${index}_${_tabKeys[index]}');
    switch (index) {
      case 0:
        return HomeScreen(key: key);
      case 1:
        return ChartScreen(key: key);
      case 2:
        return DuoScreen(key: key);
      case 3:
        return MatchListScreen(key: key);
      default:
        return HomeScreen(key: key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreen(_currentIndex),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.shade300, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _tabKeys[index]++;
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF1A1A2E),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart_rounded),
              label: '점수 추이',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_rounded),
              label: '듀오 분석',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted_rounded),
              label: '전체 기록',
            ),
          ],
        ),
      ),
    );
  }
}
