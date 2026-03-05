import 'package:flutter/material.dart';
import '../services/sheets_service.dart';

class DuoScreen extends StatefulWidget {
  const DuoScreen({super.key});

  @override
  State<DuoScreen> createState() => _DuoScreenState();
}

class _DuoScreenState extends State<DuoScreen> {
  final SheetsService _sheetsService = SheetsService();
  DuoData? _duoData;
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
      final data = await _sheetsService.fetchDuoData();
      setState(() {
        _duoData = data;
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
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          _buildHeader(),
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
                                records: _duoData!.bestDuos,
                                accentColor: Colors.blue,
                              ),
                              const SizedBox(height: 16),
                              _buildDuoSection(
                                title: '워스트 듀오 Top 3',
                                icon: Icons.sentiment_very_dissatisfied,
                                iconColor: Colors.red,
                                records: _duoData!.worstDuos,
                                accentColor: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              _buildDuoCountSection(
                                title: '듀오 횟수 TOP 3',
                                subtitle: '가장 많이 함께한 조합',
                                icon: Icons.people,
                                iconColor: Colors.green,
                                records: _duoData!.mostPlayedDuos,
                              ),
                              const SizedBox(height: 16),
                              _buildDuoCountSection(
                                title: '듀오 횟수 WORST 3',
                                subtitle: '가장 적게 함께한 조합',
                                icon: Icons.people_outline,
                                iconColor: Colors.orange,
                                records: _duoData!.leastPlayedDuos,
                              ),
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
