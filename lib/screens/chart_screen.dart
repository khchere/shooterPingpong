import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/sheets_service.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

const _playerColors = <String, Color>{
  '김기현': Color(0xFFE53935),
  '김선규': Color(0xFF1E88E5),
  '김현철': Color(0xFF43A047),
  '손신선': Color(0xFFFB8C00),
  '유민석': Color(0xFF8E24AA),
  '이동률': Color(0xFF00ACC1),
  '이선범': Color(0xFF6D4C41),
  '최권세': Color(0xFF757575),
  '한규진': Color(0xFFD81B60),
};

class _ChartScreenState extends State<ChartScreen> {
  final SheetsService _sheetsService = SheetsService();
  List<String> _players = [];
  List<DailyScore> _scores = [];
  Set<String> _visiblePlayers = {};
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
      final result = await _sheetsService.fetchDailyScores();
      setState(() {
        _players = result.players;
        _scores = result.scores;
        _visiblePlayers = result.players.toSet();
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
                              _buildChart(),
                              const SizedBox(height: 16),
                              _buildPlayerToggles(),
                              const SizedBox(height: 16),
                              _buildScoreTable(),
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
            '점수 추이',
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

  Widget _buildChart() {
    if (_scores.isEmpty) {
      return const SizedBox(
          height: 200, child: Center(child: Text('데이터 없음')));
    }

    final lines = <LineChartBarData>[];

    for (final player in _players) {
      if (!_visiblePlayers.contains(player)) continue;

      final spots = <FlSpot>[];
      for (int i = 0; i < _scores.length; i++) {
        final score = _scores[i].scores[player];
        if (score != null) {
          spots.add(FlSpot(i.toDouble(), score.toDouble()));
        }
      }

      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: _playerColors[player] ?? Colors.grey,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

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
          const Text(
            '일별 누적 점수',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                lineBarsData: lines,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: (_scores.length / 5).ceilToDouble().clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _scores.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _shortDate(_scores[idx].date),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                    left: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final playerName = _players.where(
                          (p) =>
                              _visiblePlayers.contains(p) &&
                              (_playerColors[p] ?? Colors.grey) ==
                                  spot.bar.color,
                        );
                        return LineTooltipItem(
                          '${playerName.isNotEmpty ? playerName.first : ''}: ${spot.y.toInt()}',
                          TextStyle(
                            color: spot.bar.color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
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
      final day = parts[2].trim().split(' ')[0];
      return '$month/$day';
    }
    if (date.contains('-')) {
      final parts = date.split('-');
      if (parts.length >= 3) {
        return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2].split(' ')[0]) ?? parts[2]}';
      }
    }
    return date;
  }

  Widget _buildPlayerToggles() {
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
              const Text('선수 필터',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_visiblePlayers.length == _players.length) {
                      _visiblePlayers.clear();
                    } else {
                      _visiblePlayers = _players.toSet();
                    }
                  });
                },
                child: Text(
                  _visiblePlayers.length == _players.length ? '전체 해제' : '전체 선택',
                  style: TextStyle(fontSize: 12, color: Colors.indigo.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _players.map((name) {
              final isActive = _visiblePlayers.contains(name);
              final color = _playerColors[name] ?? Colors.grey;
              return FilterChip(
                label: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isActive,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _visiblePlayers.add(name);
                    } else {
                      _visiblePlayers.remove(name);
                    }
                  });
                },
                selectedColor: color,
                checkmarkColor: Colors.white,
                backgroundColor: Colors.grey.shade200,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreTable() {
    if (_scores.isEmpty) return const SizedBox.shrink();

    final lastScore = _scores.last;
    final entries = _players
        .map((p) => MapEntry(p, lastScore.scores[p] ?? 0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
          Text(
            '최신 누적 점수 (${lastScore.date})',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...List.generate(entries.length, (i) {
            final e = entries[i];
            final color = _playerColors[e.key] ?? Colors.grey;
            final maxAbs = entries
                .map((e) => e.value.abs())
                .reduce((a, b) => a > b ? a : b)
                .clamp(1, double.infinity);
            final ratio = e.value.abs() / maxAbs;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600)),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    child: Text(e.key,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: e.value >= 0
                                  ? color.withValues(alpha: 0.3)
                                  : Colors.red.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${e.value}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: e.value >= 0 ? Colors.blue : Colors.red,
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
}
