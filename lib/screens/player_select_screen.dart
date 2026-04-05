import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sheets_service.dart';
import '../models/player_stats.dart';
import 'main_scaffold.dart';

class PlayerSelectScreen extends StatefulWidget {
  const PlayerSelectScreen({super.key});

  @override
  State<PlayerSelectScreen> createState() => _PlayerSelectScreenState();
}

class _PlayerSelectScreenState extends State<PlayerSelectScreen> {
  final SheetsService _sheetsService = SheetsService();
  final TextEditingController _nameController = TextEditingController();
  List<PlayerStats> _players = [];
  bool _isLoading = true;
  bool _isAdding = false;
  String? _error;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stats = await _sheetsService.fetchPlayerStats();
      setState(() {
        _players = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addPlayer() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final duplicate = _players.any((p) => p.name == name);
    if (duplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" 선수는 이미 등록되어 있습니다'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      await _sheetsService.addPlayer(name);
      _nameController.clear();
      FocusScope.of(context).unfocus();
      await _loadPlayers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" 선수가 등록되었습니다'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('선수 등록 실패: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedIndex == null) return;
    final name = _players[_selectedIndex!].name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_player', name);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70))
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              '데이터를 불러올 수 없습니다\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPlayers,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.sports_tennis, color: Colors.white, size: 56),
        const SizedBox(height: 16),
        const Text(
          '슈터탁구본부',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '본인의 이름을 선택해주세요',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _players.length + 1,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              itemBuilder: (context, index) {
                if (index < _players.length) {
                  final player = _players[index];
                  final isSelected = _selectedIndex == index;
                  return ListTile(
                    onTap: () => setState(() => _selectedIndex = index),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: isSelected
                          ? Colors.amber
                          : Colors.white.withValues(alpha: 0.12),
                      child: Text(
                        '${player.rank}',
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    title: Text(
                      player.name,
                      style: TextStyle(
                        color: isSelected ? Colors.amber : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    subtitle: Text(
                      '${player.wins}승 ${player.losses}패 · 승점 ${player.finalScore}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.amber, size: 28)
                        : Icon(Icons.circle_outlined,
                            color: Colors.white.withValues(alpha: 0.2), size: 28),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '새 선수 추가',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: '이름을 입력하세요',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.08),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: Colors.amber, width: 1.5),
                                ),
                              ),
                              onSubmitted: (_) => _addPlayer(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              onPressed: _isAdding ? null : _addPlayer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: const Color(0xFF1A1A2E),
                                disabledBackgroundColor:
                                    Colors.white.withValues(alpha: 0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: _isAdding
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('추가',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selectedIndex != null ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: const Color(0xFF1A1A2E),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                _selectedIndex != null
                    ? '${_players[_selectedIndex!].name}(으)로 시작'
                    : '선수를 선택해주세요',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
