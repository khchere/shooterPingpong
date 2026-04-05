import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/match_record.dart';
import '../models/player_stats.dart';
import '../services/sheets_service.dart';
import 'player_detail_screen.dart';

class _MatchCardData {
  _MatchCardData();

  int matchMode = 0;
  bool isStarted = false;
  bool isSubmitting = false;
  int? rowIndex;
  final List<String> teamA = [];
  final List<String> teamB = [];

  int get maxPerTeam => matchMode == 0 ? 2 : 1;
  bool get isTeamReady =>
      teamA.length == maxPerTeam && teamB.length == maxPerTeam;

  /// 다른 카드의 상태를 복사해 새 카드를 생성 (로컬 카드 보존용)
  factory _MatchCardData.copyFrom(_MatchCardData other) {
    final copy = _MatchCardData()
      ..matchMode = other.matchMode
      ..isStarted = other.isStarted
      ..rowIndex = other.rowIndex;
    copy.teamA.addAll(other.teamA);
    copy.teamB.addAll(other.teamB);
    return copy;
  }
}

/// 홈 프로필 카드 — 당일 경기 한 건
class _HomeTodayMatch {
  final String date;
  final bool isWin;
  final String partner;
  final String opponents;

  _HomeTodayMatch({
    required this.date,
    required this.isWin,
    required this.partner,
    required this.opponents,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SheetsService _sheetsService = SheetsService();
  List<PlayerStats> _playerStats = [];
  String _dailyDate = '';
  List<MapEntry<String, int>> _dailyRankings = [];
  bool _isLoading = true;
  String? _error;

  int _selectedPlayerIndex = 0;
  int _rankingTab = 0;
  List<_MatchCardData> _matchCards = [_MatchCardData()];
  List<String> _rankChanges = [];
  bool _bannerDismissed = false;
  List<MatchRecord> _matchRecords = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _sheetsService.fetchPlayerStats(),
        _sheetsService.fetchDailyRanking(),
        _sheetsService.fetchInProgressGames(),
        _sheetsService.fetchMatchRecords(),
      ]);
      final stats = results[0] as List<PlayerStats>;
      final daily =
          results[1] as ({String date, List<MapEntry<String, int>> rankings});
      final inProgressRecords = results[2] as List<MatchRecord>;
      final allRecords = results[3] as List<MatchRecord>;

      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('selected_player');

      final hasAnyScore = stats.any((p) => p.finalScore > 0 || p.wins > 0 || p.losses > 0);
      if (hasAnyScore) {
        final rankOrder = stats.map((p) => p.name).toList();
        await prefs.setStringList('prev_rank_order', rankOrder);
      } else {
        final savedOrder = prefs.getStringList('prev_rank_order');
        if (savedOrder != null && savedOrder.isNotEmpty) {
          stats.sort((a, b) {
            final idxA = savedOrder.indexOf(a.name);
            final idxB = savedOrder.indexOf(b.name);
            final posA = idxA >= 0 ? idxA : savedOrder.length;
            final posB = idxB >= 0 ? idxB : savedOrder.length;
            return posA.compareTo(posB);
          });
          for (int i = 0; i < stats.length; i++) {
            stats[i].rank = i + 1;
          }
        }
      }

      final changes = _detectRankChanges(prefs, stats);

      final inProgressCards = _buildInProgressCards(inProgressRecords);

      setState(() {
        _playerStats = stats;
        _dailyDate = daily.date;
        _dailyRankings = daily.rankings;
        _rankChanges = changes;
        _bannerDismissed = false;
        _matchRecords = allRecords;
        _matchCards =
            inProgressCards.isNotEmpty ? inProgressCards : [_MatchCardData()];
        if (savedName != null) {
          final idx = stats.indexWhere((p) => p.name == savedName);
          if (idx >= 0) _selectedPlayerIndex = idx;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  int _countMatchDays() {
    final dates = <String>{};
    for (final r in _matchRecords) {
      final parts = r.date.split('.');
      if (parts.length >= 3) {
        dates.add(
            '${parts[0].trim()}.${parts[1].trim()}.${parts[2].trim().split(' ')[0]}');
      }
    }
    return dates.length;
  }

  List<_MatchCardData> _buildInProgressCards(List<MatchRecord> records) {
    final inProgress = records.where((r) => r.isInProgress).toList();
    return inProgress.map((r) {
      final card = _MatchCardData();
      card.teamA.addAll([r.winner1, r.winner2].where((n) => n.isNotEmpty));
      card.teamB.addAll([r.loser1, r.loser2].where((n) => n.isNotEmpty));
      card.matchMode = card.teamA.length > 1 ? 0 : 1;
      card.isStarted = true;
      card.rowIndex = r.rowIndex;
      return card;
    }).toList();
  }

  List<String> _detectRankChanges(
      SharedPreferences prefs, List<PlayerStats> stats) {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';

    final currentMap = <String, int>{};
    for (final p in stats) {
      currentMap[p.name] = p.rank;
    }

    final prevJson = prefs.getString('prev_rankings');
    final prevDate = prefs.getString('prev_rankings_date');
    final bannerJson = prefs.getString('rank_change_banner');
    final bannerDate = prefs.getString('rank_change_banner_date');

    if (prevJson != null && prevDate != null) {
      final prevMap = Map<String, int>.from(json.decode(prevJson));

      final messages = <String>[];
      for (final p in stats) {
        final prev = prevMap[p.name];
        if (prev == null) continue;
        final diff = prev - p.rank;
        if (diff > 0) {
          messages.add('${p.name} ${prev}위→${p.rank}위 (${diff}단계 상승)');
        } else if (diff < 0) {
          messages.add('${p.name} ${prev}위→${p.rank}위 (${diff.abs()}단계 하락)');
        }
      }

      if (messages.isNotEmpty) {
        prefs.setString('rank_change_banner', json.encode(messages));
        prefs.setString('rank_change_banner_date', todayKey);
      }

      prefs.setString('prev_rankings', json.encode(currentMap));
      prefs.setString('prev_rankings_date', todayKey);

      if (messages.isNotEmpty) return messages;
    } else {
      prefs.setString('prev_rankings', json.encode(currentMap));
      prefs.setString('prev_rankings_date', todayKey);
    }

    if (bannerJson != null && bannerDate == todayKey) {
      return List<String>.from(json.decode(bannerJson));
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildHeader(),
                        if (_rankChanges.isNotEmpty && !_bannerDismissed)
                          _buildRankChangeBanner(),
                        _buildPlayerCard(),
                        _buildRankingCard(),
                        ...List.generate(
                          _matchCards.length,
                          (i) => _buildMatchCard(i),
                        ),
                        _buildAddMatchButton(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 16,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A2E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.sports_tennis, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '슈터탁구본부',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '2026년시즌2 · 매치데이 ${_countMatchDays()}',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: Colors.grey.shade600, size: 22),
            onPressed: _loadData,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (value) {
              if (value == 'archive') _showArchiveDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('시즌 아카이브'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showArchiveDialog() async {
    final nameController = TextEditingController(text: '26년시즌2');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('시즌 아카이브'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재까지의 모든 기록을 별도 시즌으로 저장하고,\n랭킹과 기록을 초기화합니다.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: '시즌 이름',
                hintText: '예: 26년시즌1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '이 작업은 되돌릴 수 없습니다!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A2E),
              foregroundColor: Colors.white,
            ),
            child: const Text('아카이브 실행'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final seasonName = nameController.text.trim();
    if (seasonName.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Row(
            children: [
              SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(width: 24),
              Expanded(
                child: Text('시즌 아카이브 처리 중…\n잠시 기다려주세요.',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await _sheetsService.archiveSeason(seasonName);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$seasonName" 시즌이 아카이브되었습니다. 새 시즌이 시작됩니다!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('아카이브 실패: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Rank Change Banner ──
  Widget _buildRankChangeBanner() {
    final upChanges = _rankChanges.where((m) => m.contains('상승')).toList();
    final downChanges = _rankChanges.where((m) => m.contains('하락')).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade50, Colors.orange.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign, size: 18, color: Colors.orange),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '랭킹 변동 알림',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _bannerDismissed = true),
                child: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...upChanges.map((msg) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward,
                        size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(msg,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.blue)),
                    ),
                  ],
                ),
              )),
          ...downChanges.map((msg) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_downward,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(msg,
                          style:
                              const TextStyle(fontSize: 13, color: Colors.red)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _extractDateKey(String date) {
    final trimmed = date.trim();
    final parts = trimmed.split('.');
    if (parts.length >= 3) {
      final y = parts[0].trim();
      final m = parts[1].trim();
      final d = parts[2].trim().split(' ')[0];
      return '$y.$m.$d';
    }
    return trimmed.split(' ').first;
  }

  Set<String> _todayDateKeys() {
    final now = DateTime.now();
    return {
      '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}',
      '${now.year}.${now.month}.${now.day}',
    };
  }

  /// 시트 순서(오래된 것 먼저)로 당일 경기만 수집
  List<_HomeTodayMatch> _todayMatchesChronological(String playerName) {
    final keys = _todayDateKeys();
    final out = <_HomeTodayMatch>[];
    for (final r in _matchRecords) {
      if (r.isInProgress) continue;
      final dateKey = _extractDateKey(r.date);
      if (!keys.contains(dateKey)) continue;

      final winners = [r.winner1, r.winner2].where((n) => n.isNotEmpty).toSet();
      final losers = [r.loser1, r.loser2].where((n) => n.isNotEmpty).toSet();
      if (!winners.contains(playerName) && !losers.contains(playerName)) {
        continue;
      }
      final isWin = winners.contains(playerName);
      final myTeam = isWin ? winners : losers;
      final opTeam = isWin ? losers : winners;
      final partner = myTeam.where((n) => n != playerName).join(', ');
      final opponents = opTeam.join(', ');
      out.add(_HomeTodayMatch(
        date: r.date,
        isWin: isWin,
        partner: partner,
        opponents: opponents,
      ));
    }
    return out;
  }

  String _shortDateLabel(String date) {
    final parts = date.split('.');
    if (parts.length >= 3) {
      final month = parts[1].trim();
      final dayPart = parts[2].trim().split(' ');
      return '${month}/${dayPart[0]}';
    }
    return date;
  }

  Widget _buildTodayWlChip(_HomeTodayMatch g) {
    return Container(
      width: 28,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: g.isWin
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        g.isWin ? 'W' : 'L',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: g.isWin ? Colors.blue : Colors.red,
        ),
      ),
    );
  }

  Widget _buildTodayGameDetailRow(_HomeTodayMatch g) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: g.isWin
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                g.isWin ? 'W' : 'L',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: g.isWin ? Colors.blue : Colors.red,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.partner.isEmpty
                      ? 'vs ${g.opponents}'
                      : '${g.partner}(과) vs ${g.opponents}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _shortDateLabel(g.date),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 프로필 카드 내 당일 경기 (최근경기 UI와 동일 톤, 상세는 ExpansionTile)
  Widget _buildProfileTodayGames(PlayerStats player) {
    final chronological = _todayMatchesChronological(player.name);
    if (chronological.isEmpty) return const SizedBox.shrink();

    // 선수 상세 화면 '최근 경기'와 동일: 최신이 앞(왼쪽)
    final display = chronological.reversed.toList();
    final winCount = display.where((g) => g.isWin).length;
    final loseCount = display.length - winCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            initiallyExpanded: false,
            title: Row(
              children: [
                const Text(
                  '오늘 경기',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${display.length}경기 · $winCount승 $loseCount패',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: display.length,
                  physics: const BouncingScrollPhysics(),
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, i) => _buildTodayWlChip(display[i]),
                ),
              ),
            ),
            children: display.map(_buildTodayGameDetailRow).toList(),
          ),
        ),
      ],
    );
  }

  // ── Player Card ──
  Widget _buildPlayerCard() {
    if (_playerStats.isEmpty) return const SizedBox.shrink();

    final player = _playerStats[_selectedPlayerIndex];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerDetailScreen(player: player),
          ),
        ),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showPlayerPicker(),
                    child: Row(
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_drop_down,
                            size: 22, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${player.rank}위',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: player.rank <= 3 ? Colors.red : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            if (player.currentStreak != 0) ...[
              const SizedBox(height: 8),
              _buildStreakBadge(player),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '참여율',
                  '${player.participationRate.toStringAsFixed(1)}%',
                ),
                _buildStatItem(
                  '승률',
                  '${player.winRate.toStringAsFixed(1)}%',
                ),
                _buildStatItem(
                  '승점',
                  '${player.finalScore}점',
                ),
              ],
            ),
            _buildProfileTodayGames(player),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakBadge(PlayerStats player) {
    final streak = player.currentStreak;
    final isWin = streak > 0;
    final count = streak.abs();
    final color = isWin ? Colors.blue : Colors.red;
    final icon = isWin ? Icons.local_fire_department : Icons.trending_down;
    final label = isWin ? '$count연승 중!' : '$count연패 중';
    final maxLabel =
        isWin ? '최장 ${player.maxWinStreak}연승' : '최장 ${player.maxLoseStreak}연패';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            maxLabel,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showPlayerPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _playerStats.length,
          itemBuilder: (context, index) {
            final p = _playerStats[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: index == _selectedPlayerIndex
                    ? Colors.indigo
                    : Colors.grey.shade300,
                child: Text(
                  '${p.rank}',
                  style: TextStyle(
                    color: index == _selectedPlayerIndex
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${p.wins}승 ${p.losses}패 · 최종 ${p.finalScore}점'),
              selected: index == _selectedPlayerIndex,
              onTap: () async {
                setState(() => _selectedPlayerIndex = index);
                Navigator.pop(context);
                // final prefs = await SharedPreferences.getInstance();
                // await prefs.setString('selected_player', p.name);
              },
            );
          },
        );
      },
    );
  }

  // ── Ranking Card (탭 전환) ──
  Widget _buildRankingCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildRankingTabs(),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _rankingTab == 0
                ? _buildDailyRankingContent()
                : _buildOverallRankingContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildTabButton(0, '당일 랭킹'),
          _buildTabButton(1, '통합 랭킹'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _rankingTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _rankingTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color:
                  isSelected ? const Color(0xFF1A1A2E) : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  // ── 당일 랭킹 콘텐츠 ──
  Widget _buildDailyRankingContent() {
    if (_dailyRankings.isEmpty) {
      return const Padding(
        key: ValueKey('daily_empty'),
        padding: EdgeInsets.all(24),
        child: Center(child: Text('당일 데이터 없음')),
      );
    }

    return Column(
      key: const ValueKey('daily'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            _dailyDate,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        const SizedBox(height: 4),
        ...List.generate(_dailyRankings.length, (index) {
          final entry = _dailyRankings[index];
          final name = entry.key;
          final change = entry.value;
          final isCurrentPlayer = _playerStats.isNotEmpty &&
              _playerStats[_selectedPlayerIndex].name == name;

          Color scoreColor;
          String prefix;
          IconData icon;
          if (change > 0) {
            scoreColor = Colors.blue;
            prefix = '+';
            icon = Icons.arrow_drop_up;
          } else if (change < 0) {
            scoreColor = Colors.red;
            prefix = '';
            icon = Icons.arrow_drop_down;
          } else {
            scoreColor = Colors.grey;
            prefix = '';
            icon = Icons.remove;
          }

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: isCurrentPlayer ? Colors.red.shade50 : null,
              borderRadius: isCurrentPlayer ? BorderRadius.circular(8) : null,
              border: isCurrentPlayer
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade200,
                        width: index < _dailyRankings.length - 1 ? 0.5 : 0,
                      ),
                    ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isCurrentPlayer
                          ? Colors.red
                          : index < 3
                              ? const Color(0xFF1A1A2E)
                              : Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrentPlayer ? Colors.red : Colors.black87,
                    ),
                  ),
                ),
                Icon(icon, color: scoreColor, size: 22),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$prefix$change',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── 통합 랭킹 콘텐츠 ──
  Widget _buildOverallRankingContent() {
    return Column(
      key: const ValueKey('overall'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: const [
              SizedBox(
                width: 40,
                child: Text('랭킹',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              Expanded(
                flex: 2,
                child: Text('이름',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              Expanded(
                flex: 3,
                child: Text('전적',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              Expanded(
                flex: 2,
                child: Text('최종 점수',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...List.generate(
          _playerStats.length,
          (index) => _buildOverallRankingRow(_playerStats[index]),
        ),
      ],
    );
  }

  Widget _buildOverallRankingRow(PlayerStats player) {
    final isCurrentPlayer = _playerStats.isNotEmpty &&
        _playerStats[_selectedPlayerIndex].name == player.name;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isCurrentPlayer ? Colors.red.shade50 : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${player.rank}위',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isCurrentPlayer ? Colors.red : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              player.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isCurrentPlayer ? Colors.red : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${player.totalGames}전 ${player.wins}승 ${player.losses}패',
              style: TextStyle(
                fontSize: 12,
                color: isCurrentPlayer
                    ? Colors.red.shade400
                    : Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${player.finalScore}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: player.finalScore > 0
                    ? Colors.blue
                    : player.finalScore < 0
                        ? Colors.red
                        : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Match Cards ──
  double _teamWinRate(List<String> team) {
    if (team.isEmpty) return 50;
    double sum = 0;
    int count = 0;
    for (final name in team) {
      final stat = _playerStats.where((p) => p.name == name).firstOrNull;
      if (stat != null && (stat.wins + stat.losses) > 0) {
        sum += stat.winRate;
        count++;
      }
    }
    return count > 0 ? sum / count : 50;
  }

  ({double teamA, double teamB}) _predictWinRate(_MatchCardData card) {
    final rateA = _teamWinRate(card.teamA);
    final rateB = _teamWinRate(card.teamB);
    final total = rateA + rateB;
    if (total == 0) return (teamA: 50, teamB: 50);
    return (
      teamA: (rateA / total * 100),
      teamB: (rateB / total * 100),
    );
  }

  Widget _buildPrediction(_MatchCardData card) {
    final pred = _predictWinRate(card);
    final aWin = pred.teamA;
    final bWin = pred.teamB;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            '예상 승률',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${aWin.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: aWin >= bWin ? Colors.blue : Colors.blue.shade200,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: aWin.round().clamp(1, 99),
                          child: Container(color: Colors.blue),
                        ),
                        Expanded(
                          flex: bWin.round().clamp(1, 99),
                          child: Container(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${bWin.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: bWin >= aWin ? Colors.red : Colors.red.shade200,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddMatchButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _matchCards.add(_MatchCardData())),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('경기 추가'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A1A2E),
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildMatchCard(int cardIndex) {
    final card = _matchCards[cardIndex];
    final allNames = _playerStats.map((p) => p.name).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                card.isStarted
                    ? '경기 ${cardIndex + 1}'
                    : (_matchCards.length > 1
                        ? '경기 ${cardIndex + 1}'
                        : '경기 기록'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (card.isStarted) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(
                    '진행중',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (card.isStarted)
                GestureDetector(
                  onTap: () => _cancelGame(cardIndex),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      '경기취소',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ),
              if (!card.isStarted && _matchCards.length > 1) ...[
                if (card.isStarted) const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _matchCards.removeAt(cardIndex)),
                  child:
                      Icon(Icons.close, size: 20, color: Colors.grey.shade400),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _buildMatchModeTabs(card),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTeamBox(
                    'A팀', card.teamA, Colors.blue, allNames, card),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
              Expanded(
                child:
                    _buildTeamBox('B팀', card.teamB, Colors.red, allNames, card),
              ),
            ],
          ),
          if (card.isTeamReady && !card.isStarted) ...[
            const SizedBox(height: 12),
            _buildPrediction(card),
          ],
          const SizedBox(height: 16),
          if (card.isSubmitting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (card.isTeamReady)
            _buildWinnerSelection(cardIndex),
        ],
      ),
    );
  }

  Future<void> _cancelGame(int cardIndex) async {
    final card = _matchCards[cardIndex];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('경기취소'),
        content: const Text('진행중인 경기를 취소하시겠습니까?\n기록도 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('경기취소'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (card.rowIndex != null) {
        await _sheetsService.cancelInProgressGame(card.rowIndex!);
      }

      setState(() {
        if (_matchCards.length > 1) {
          _matchCards.removeAt(cardIndex);
        } else {
          card.teamA.clear();
          card.teamB.clear();
          card.isStarted = false;
          card.rowIndex = null;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('경기가 취소되었습니다'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('경기취소 실패: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Widget _buildWinnerSelection(int cardIndex) {
    final card = _matchCards[cardIndex];

    if (card.isSubmitting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        Text(
          '승리 팀을 선택하세요',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () =>
                      _submitResult(cardIndex, isTeamAWinner: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'A팀 승리',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () =>
                      _submitResult(cardIndex, isTeamAWinner: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'B팀 승리',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatchModeTabs(_MatchCardData card) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildModeTabButton(0, '2 vs 2', card),
          _buildModeTabButton(1, '1 vs 1', card),
        ],
      ),
    );
  }

  Widget _buildModeTabButton(int index, String label, _MatchCardData card) {
    final isSelected = card.matchMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: card.isStarted
            ? null
            : () {
                setState(() {
                  card.matchMode = index;
                  card.teamA.clear();
                  card.teamB.clear();
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color:
                  isSelected ? const Color(0xFF1A1A2E) : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  /// 5분 이내에 동일한 팀 구성의 경기 기록이 있는지 확인
  bool _hasDuplicateRecord(List<String> winners, List<String> losers) {
    final winSet = winners.where((n) => n.isNotEmpty).toSet();
    final loseSet = losers.where((n) => n.isNotEmpty).toSet();
    final allPlayers = {...winSet, ...loseSet};

    final now = DateTime.now();
    for (final r in _matchRecords.reversed) {
      // 날짜 파싱 (형식: "YYYY.MM.DD HH:mm" 또는 "YYYY.M.D H:mm")
      DateTime? recordTime;
      try {
        final trimmed = r.date.trim();
        final spaceIdx = trimmed.indexOf(' ');
        if (spaceIdx >= 0) {
          final datePart = trimmed.substring(0, spaceIdx);
          final timePart = trimmed.substring(spaceIdx + 1);
          final dateParts = datePart.split('.');
          final timeParts = timePart.split(':');
          if (dateParts.length >= 3 && timeParts.length >= 2) {
            recordTime = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          }
        }
      } catch (_) {
        continue;
      }
      if (recordTime == null) continue;

      // 5분 초과한 기록은 무시
      if (now.difference(recordTime).inMinutes > 5) continue;

      final rWinSet = {r.winner1, r.winner2}.where((n) => n.isNotEmpty).toSet();
      final rLoseSet = {r.loser1, r.loser2}.where((n) => n.isNotEmpty).toSet();
      final rAllPlayers = {...rWinSet, ...rLoseSet};

      // 팀 구성이 동일한지 확인 (팀 순서 무관)
      if (rAllPlayers.length == allPlayers.length &&
          rAllPlayers.containsAll(allPlayers) &&
          ((rWinSet.containsAll(winSet) && rLoseSet.containsAll(loseSet)) ||
              (rWinSet.containsAll(loseSet) && rLoseSet.containsAll(winSet)))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _submitResult(int cardIndex,
      {required bool isTeamAWinner}) async {
    final card = _matchCards[cardIndex];
    final winners = isTeamAWinner ? card.teamA : card.teamB;
    final losers = isTeamAWinner ? card.teamB : card.teamA;

    // 현재 선택된 플레이어가 승리팀에 포함됐는지 미리 확인 (비동기 전에 캡처)
    final currentPlayerName =
        _playerStats.isNotEmpty ? _playerStats[_selectedPlayerIndex].name : '';
    final currentPlayerWon = winners.contains(currentPlayerName);
    final winTeamCopy = List<String>.from(winners);

    final winner1 = winners[0];
    final winner2 = winners.length > 1 ? winners[1] : '';
    final loser1 = losers[0];
    final loser2 = losers.length > 1 ? losers[1] : '';

    final winnerText = winner2.isEmpty ? winner1 : '$winner1, $winner2';
    final loserText = loser2.isEmpty ? loser1 : '$loser1, $loser2';

    // 5분 이내 동일 팀 구성 기록 존재 시 경고 얼럿
    if (_hasDuplicateRecord(winners, losers)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade600, size: 22),
              const SizedBox(width: 8),
              const Text('중복 기록 감지'),
            ],
          ),
          content: const Text(
            '최근 동일한 저장 기록이 존재합니다.\n저장하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('경기 결과 저장'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('승: $winnerText',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.close, color: Colors.red.shade300, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('패: $loserText',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('이 결과를 저장하시겠습니까?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A2E),
              foregroundColor: Colors.white,
            ),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => card.isSubmitting = true);

    try {
      if (card.rowIndex != null) {
        await _sheetsService.completeGame(
          rowIndex: card.rowIndex!,
          winner1: winner1,
          winner2: winner2,
          loser1: loser1,
          loser2: loser2,
        );
      } else {
        await _sheetsService.submitMatchResult(
          winner1: winner1,
          winner2: winner2,
          loser1: loser1,
          loser2: loser2,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 완료! 승: $winnerText'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // _loadData 전에 다른 로컬 카드 상태 백업
      // (rowIndex가 없는 카드 = 서버에 저장되지 않은 로컬 카드, 제출 카드 제외)
      final savedLocalCards = _matchCards
          .where((c) => c != card && c.rowIndex == null)
          .map((c) => _MatchCardData.copyFrom(c))
          .toList();

      // _loadData가 _matchCards를 새로 초기화하므로 먼저 await
      await _loadData();

      // 로드 완료 후 복원
      if (!mounted) return;
      setState(() {
        // 백업해둔 로컬 카드 복원
        _matchCards.addAll(savedLocalCards);

        // A팀 복원 (첫 번째 카드 기준)
        if (currentPlayerName.isNotEmpty && _matchCards.isNotEmpty) {
          if (currentPlayerWon) {
            // 이긴 경우: 승리팀 전체 유지
            _matchCards[0].teamA
              ..clear()
              ..addAll(winTeamCopy);
          } else {
            // 진 경우: 내 이름만 A팀에 남김
            _matchCards[0].teamA
              ..clear()
              ..add(currentPlayerName);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => card.isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 실패: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildTeamBox(
    String label,
    List<String> team,
    Color color,
    List<String> allNames,
    _MatchCardData card,
  ) {
    final availableNames = allNames
        .where((n) => !card.teamA.contains(n) && !card.teamB.contains(n))
        .toList();
    final needMore = team.length < card.maxPerTeam && !card.isStarted;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          // 선택된 선수 칩
          ...team.map(
            (name) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Chip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                deleteIcon:
                    card.isStarted ? null : const Icon(Icons.close, size: 16),
                onDeleted: card.isStarted
                    ? null
                    : () => setState(() => team.remove(name)),
                backgroundColor: color.withValues(alpha: 0.15),
                side: BorderSide(color: color.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          // 추가 가능한 선수 인라인 칩
          if (needMore && availableNames.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: availableNames
                  .map(
                    (name) => GestureDetector(
                      onTap: () => setState(() => team.add(name)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: color.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: color.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (needMore && availableNames.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '선택 가능한 선수 없음',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
        ],
      ),
    );
  }
}
