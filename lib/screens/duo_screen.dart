import 'package:flutter/material.dart';
import '../models/match_record.dart';
import '../services/sheets_service.dart';

class DuoScreen extends StatefulWidget {
  const DuoScreen({super.key});

  @override
  State<DuoScreen> createState() => _DuoScreenState();
}

class _DuoScreenState extends State<DuoScreen> {
  final SheetsService _sheetsService = SheetsService();
  DuoData? _duoData;
  DuoData? _allSeasonsData;
  int _tab = 0; // 0: 현재 시즌, 1: 전체 시즌
  bool _showAllRanked = false;
  String? _partnerA;
  String? _partnerB;
  bool _isLoading = true;
  String? _error;

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
        _sheetsService.fetchDuoData(),
        _sheetsService.fetchDuoDataAllSeasons(),
      ]);
      setState(() {
        _duoData = results[0];
        _allSeasonsData = results[1];
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
  Widget build(BuildContext context) {
    final data = _tab == 0 ? _duoData : _allSeasonsData;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          _buildHeader(),
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildSeasonTabs(),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildDuoSection(
                                title: '베스트 듀오 Top 3',
                                icon: Icons.emoji_events,
                                iconColor: Colors.amber,
                                records: data!.bestDuos,
                                accentColor: Colors.blue,
                              ),
                              const SizedBox(height: 16),
                              _buildDuoSection(
                                title: '워스트 듀오 Top 3',
                                icon: Icons.sentiment_very_dissatisfied,
                                iconColor: Colors.red,
                                records: data.worstDuos,
                                accentColor: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              _buildAllRankedSection(data.allRankedDuos),
                              const SizedBox(height: 16),
                              _buildDuoCountSection(
                                title: '듀오 횟수 TOP 3',
                                subtitle: '가장 많이 함께한 조합',
                                icon: Icons.people,
                                iconColor: Colors.green,
                                records: data.mostPlayedDuos,
                              ),
                              const SizedBox(height: 16),
                              _buildDuoCountSection(
                                title: '듀오 횟수 WORST 3',
                                subtitle: '가장 적게 함께한 조합',
                                icon: Icons.people_outline,
                                iconColor: Colors.orange,
                                records: data.leastPlayedDuos,
                              ),
                              const SizedBox(height: 16),
                              _buildPartnerDetailSection(data.records),
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

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
      child: Row(
        children: [
          const Text(
            '듀오 분석',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
            onPressed: _loadData,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildTabButton(0, '현재 시즌'),
          _buildTabButton(1, '전체 시즌'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
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

  // ── 파트너 세부 전적 (시트 '파트너 전적' 탭) ──
  Widget _buildPartnerDetailSection(List<MatchRecord> records) {
    final names = <String>{};
    for (final r in records) {
      if (r.winner2.trim().isEmpty || r.loser2.trim().isEmpty) continue;
      names.addAll([r.winner1, r.winner2, r.loser1, r.loser2]
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty));
    }
    final players = names.toList()..sort();
    // 시즌 탭 전환 등으로 명단에서 빠진 선택은 무효화
    final a = players.contains(_partnerA) ? _partnerA : null;
    final b = players.contains(_partnerB) ? _partnerB : null;
    final detail = (a != null && b != null && a != b)
        ? _sheetsService.buildDuoDetail(records, a, b)
        : null;

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
              const Icon(Icons.handshake, color: Colors.purple, size: 22),
              const SizedBox(width: 8),
              const Text('파트너 세부 전적',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('두 선수가 한 팀일 때의 상대별 전적',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPlayerDropdown(
                  label: '선수 A',
                  value: a,
                  players: players,
                  onChanged: (v) => setState(() => _partnerA = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPlayerDropdown(
                  label: '선수 B',
                  value: b,
                  players: players,
                  onChanged: (v) => setState(() => _partnerB = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (detail == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  a != null && a == b ? '서로 다른 선수를 선택하세요' : '두 선수를 선택하세요',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else if (detail.total == 0)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('함께한 경기 없음')),
            )
          else ...[
            _buildDetailSummary(detail),
            const SizedBox(height: 12),
            _buildDetailTable('상대 조합', detail.vsPairs),
            const SizedBox(height: 12),
            _buildDetailTable('상대 (개인)', detail.vsPlayers),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerDropdown({
    required String label,
    required String? value,
    required List<String> players,
    required ValueChanged<String?> onChanged,
  }) {
    // 시즌 탭 전환으로 명단이 바뀌어도 선택값을 그대로 반영하도록 value 제어형 사용
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          hint: const Text('선택'),
          items: players
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDetailSummary(DuoDetail detail) {
    final rate = (detail.wins / detail.total * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryItem('경기', '${detail.total}', Colors.black87),
          _buildSummaryItem('승', '${detail.wins}', Colors.blue.shade700),
          _buildSummaryItem('패', '${detail.losses}', Colors.red.shade700),
          _buildSummaryItem('승률', '$rate%', Colors.purple),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildDetailTable(String firstColumn, List<DuoRecord> records) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                  flex: 4,
                  child: Text(firstColumn,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey))),
              const Expanded(
                  flex: 2,
                  child: Text('승',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center)),
              const Expanded(
                  flex: 2,
                  child: Text('패',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center)),
              const Expanded(
                  flex: 2,
                  child: Text('승률',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center)),
            ],
          ),
        ),
        const Divider(height: 1),
        ...records.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(r.team,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.wins}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.blue.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.losses}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.red.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(r.winRate,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )),
      ],
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

  // ── 전체 듀오 순위 (접이식) ──
  Widget _buildAllRankedSection(List<DuoRecord> records) {
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
          GestureDetector(
            onTap: () => setState(() => _showAllRanked = !_showAllRanked),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.format_list_numbered,
                    color: Colors.indigo, size: 22),
                const SizedBox(width: 8),
                const Text('전체 듀오 순위',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${records.length}개 조합 · 10전 이상',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showAllRanked ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
          if (_showAllRanked) ...[
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                      width: 28,
                      child: Text('#',
                          style: TextStyle(fontSize: 12, color: Colors.grey))),
                  Expanded(
                      flex: 4,
                      child: Text('팀 조합',
                          style: TextStyle(fontSize: 12, color: Colors.grey))),
                  Expanded(
                      flex: 2,
                      child: Text('경기',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('승',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('패',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('승률',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
            const Divider(height: 1),
            ...List.generate(records.length, (index) {
              final r = records[index];
              final games = r.wins + r.losses;
              final rate = games > 0 ? r.wins / games : 0.0;
              final rateColor =
                  rate >= 0.5 ? Colors.blue.shade700 : Colors.red.shade700;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${index + 1}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600)),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(r.team,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('$games',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('${r.wins}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: Colors.blue.shade700)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('${r.losses}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: Colors.red.shade700)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(r.winRate,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: rateColor)),
                    ),
                  ],
                ),
              );
            }),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('데이터 없음')),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuoSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<DuoRecord> records,
    required Color accentColor,
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
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '10전 이상',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Expanded(
                    flex: 4,
                    child: Text('팀 조합',
                        style: TextStyle(fontSize: 12, color: Colors.grey))),
                const Expanded(
                    flex: 2,
                    child: Text('승',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
                const Expanded(
                    flex: 2,
                    child: Text('패',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
                const Expanded(
                    flex: 2,
                    child: Text('승률',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...List.generate(records.length, (index) {
            final r = records[index];
            final medal = index == 0
                ? '🥇'
                : index == 1
                    ? '🥈'
                    : '🥉';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Text(medal, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: Text(r.team,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.wins}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.blue.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.losses}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.red.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(r.winRate,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: accentColor)),
                  ),
                ],
              ),
            );
          }),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('데이터 없음')),
            ),
        ],
      ),
    );
  }

  Widget _buildDuoCountSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<DuoRecord> records,
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
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: const [
                Expanded(
                    flex: 4,
                    child: Text('팀 조합',
                        style: TextStyle(fontSize: 12, color: Colors.grey))),
                Expanded(
                    flex: 2,
                    child: Text('합계',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('승',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('패',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('승률',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...List.generate(records.length, (index) {
            final r = records[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(r.team,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.totalGames ?? 0}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.wins}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.blue.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${r.losses}',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Colors.red.shade700)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(r.winRate,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('데이터 없음')),
            ),
        ],
      ),
    );
  }
}
