import 'package:flutter/material.dart';
import '../models/match_record.dart';
import '../models/player_stats.dart';
import '../services/sheets_service.dart';

class PlayerDetailScreen extends StatefulWidget {
  final PlayerStats player;

  const PlayerDetailScreen({super.key, required this.player});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  final SheetsService _sheetsService = SheetsService();
  List<MatchRecord> _records = [];
  bool _isLoading = true;

  List<_PlayerMatchResult> _myGames = [];
  Map<String, _HeadToHead> _h2h = {};
  Map<String, _PartnerRecord> _partners = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final records = await _sheetsService.fetchMatchRecords();
      _records = records;
      _analyze();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _analyze() {
    final name = widget.player.name;
    final games = <_PlayerMatchResult>[];
    final h2h = <String, _HeadToHead>{};
    final partners = <String, _PartnerRecord>{};

    for (final r in _records) {
      final winners = [r.winner1, r.winner2].where((n) => n.isNotEmpty).toSet();
      final losers = [r.loser1, r.loser2].where((n) => n.isNotEmpty).toSet();

      if (!winners.contains(name) && !losers.contains(name)) continue;

      final isWin = winners.contains(name);
      final myTeam = isWin ? winners : losers;
      final opTeam = isWin ? losers : winners;
      final partner = myTeam.where((n) => n != name).join(', ');
      final opponents = opTeam.join(', ');

      games.add(_PlayerMatchResult(
        date: r.date,
        isWin: isWin,
        partner: partner,
        opponents: opponents,
      ));

      for (final op in opTeam) {
        h2h.putIfAbsent(op, () => _HeadToHead(op));
        if (isWin) {
          h2h[op]!.wins++;
        } else {
          h2h[op]!.losses++;
        }
      }

      if (partner.isNotEmpty && !partner.contains(',')) {
        partners.putIfAbsent(partner, () => _PartnerRecord(partner));
        if (isWin) {
          partners[partner]!.wins++;
        } else {
          partners[partner]!.losses++;
        }
      }
    }

    _myGames = games;
    _h2h = h2h;
    _partners = partners;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          _buildHeader(p),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSummaryCard(p),
                          const SizedBox(height: 16),
                          _buildRecentGames(),
                          const SizedBox(height: 16),
                          _buildH2HSection(),
                          const SizedBox(height: 16),
                          _buildPartnerSection(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(PlayerStats p) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            p.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: p.rank <= 3
                  ? Colors.red
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${p.rank}위',
              style: TextStyle(
                color: p.rank <= 3 ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(PlayerStats p) {
    return Container(
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
      child: Column(
        children: [
          Row(
            children: [
              _statCell('승률', '${p.winRate.toStringAsFixed(1)}%'),
              _divider(),
              _statCell('승점', '${p.finalScore}점'),
              _divider(),
              _statCell('참여율', '${p.participationRate.toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _statCell('전적', '${p.totalGames}전 ${p.wins}승 ${p.losses}패'),
                _divider(),
                _statCell('최장 연승', '${p.maxWinStreak}연승'),
                _divider(),
                _statCell('최장 연패', '${p.maxLoseStreak}연패'),
              ],
            ),
          ),
          if (p.currentStreak != 0) ...[
            const SizedBox(height: 12),
            _buildStreakRow(p),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.grey.shade200,
    );
  }

  Widget _buildStreakRow(PlayerStats p) {
    final isWin = p.currentStreak > 0;
    final color = isWin ? Colors.blue : Colors.red;
    final icon = isWin ? Icons.local_fire_department : Icons.trending_down;
    final text = isWin
        ? '${p.currentStreak}연승 진행 중!'
        : '${p.currentStreak.abs()}연패 진행 중';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ── 최근 경기 ──
  Widget _buildRecentGames() {
    final recent = _myGames.reversed.take(15).toList();
    if (recent.isEmpty) return const SizedBox.shrink();

    return _card(
      title: '최근 경기',
      trailing: '${_myGames.length}경기 중 최근 15경기',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: recent.map((g) {
                return Expanded(
                  child: Container(
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: g.isWin
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        g.isWin ? 'W' : 'L',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: g.isWin ? Colors.blue : Colors.red,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ...recent.take(10).map((g) => _gameRow(g)),
        ],
      ),
    );
  }

  Widget _gameRow(_PlayerMatchResult g) {
    final dateShort = _shortDate(g.date);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
        ),
      ),
      child: Row(
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
                      fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dateShort,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortDate(String date) {
    final parts = date.split('.');
    if (parts.length >= 3) {
      final month = parts[1].trim();
      final dayPart = parts[2].trim().split(' ');
      return '${month}/${dayPart[0]}';
    }
    return date;
  }

  // ── 상대 전적 ──
  Widget _buildH2HSection() {
    if (_h2h.isEmpty) return const SizedBox.shrink();

    final sorted = _h2h.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return _card(
      title: '상대 전적',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(
                    width: 50,
                    child: Text('상대',
                        style: TextStyle(fontSize: 11, color: Colors.grey))),
                const Expanded(
                    child: Text('전적',
                        style: TextStyle(fontSize: 11, color: Colors.grey))),
                const SizedBox(
                    width: 60,
                    child: Text('승률',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...sorted.map((h) {
            final rate = h.total > 0 ? h.wins / h.total * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(h.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${h.total}전 ${h.wins}승 ${h.losses}패',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: Row(
                                children: [
                                  if (h.wins > 0)
                                    Expanded(
                                      flex: h.wins,
                                      child: Container(color: Colors.blue),
                                    ),
                                  if (h.losses > 0)
                                    Expanded(
                                      flex: h.losses,
                                      child: Container(color: Colors.red),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${rate.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: rate >= 50 ? Colors.blue : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 파트너 전적 ──
  Widget _buildPartnerSection() {
    if (_partners.isEmpty) return const SizedBox.shrink();

    final sorted = _partners.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return _card(
      title: '파트너 전적',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const SizedBox(
                    width: 50,
                    child: Text('파트너',
                        style: TextStyle(fontSize: 11, color: Colors.grey))),
                const Expanded(
                    child: Text('전적',
                        style: TextStyle(fontSize: 11, color: Colors.grey))),
                const SizedBox(
                    width: 60,
                    child: Text('승률',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...sorted.map((pr) {
            final rate = pr.total > 0 ? pr.wins / pr.total * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(pr.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${pr.total}전 ${pr.wins}승 ${pr.losses}패',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: Row(
                                children: [
                                  if (pr.wins > 0)
                                    Expanded(
                                      flex: pr.wins,
                                      child: Container(color: Colors.blue),
                                    ),
                                  if (pr.losses > 0)
                                    Expanded(
                                      flex: pr.losses,
                                      child: Container(color: Colors.red),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${rate.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: rate >= 50 ? Colors.blue : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    String? trailing,
    required Widget child,
  }) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (trailing != null) ...[
                const Spacer(),
                Text(trailing,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PlayerMatchResult {
  final String date;
  final bool isWin;
  final String partner;
  final String opponents;

  _PlayerMatchResult({
    required this.date,
    required this.isWin,
    required this.partner,
    required this.opponents,
  });
}

class _HeadToHead {
  final String name;
  int wins = 0;
  int losses = 0;

  _HeadToHead(this.name);

  int get total => wins + losses;
}

class _PartnerRecord {
  final String name;
  int wins = 0;
  int losses = 0;

  _PartnerRecord(this.name);

  int get total => wins + losses;
}
