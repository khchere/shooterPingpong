import 'package:flutter/material.dart';
import '../models/match_record.dart';
import '../services/sheets_service.dart';

class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  final SheetsService _sheetsService = SheetsService();
  late Future<List<MatchRecord>> _matchRecords;

  @override
  void initState() {
    super.initState();
    _matchRecords = _sheetsService.fetchMatchRecords();
  }

  /// fetch 완료 후 이미 완료된 Future로 갱신 → Dismissible.confirmDismiss 중
  /// 리스트가 통째로 로딩 상태로 바뀌며 위젯이 dispose되는 문제를 방지합니다.
  Future<void> _refresh() async {
    try {
      final data = await _sheetsService.fetchMatchRecords();
      if (!mounted) return;
      setState(() {
        _matchRecords = Future.value(data);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _matchRecords = Future.error(e, st);
      });
    }
  }

  String _extractDate(String fullDate) {
    final parts = fullDate.split('.');
    if (parts.length >= 3) {
      final year = parts[0].trim();
      final month = parts[1].trim();
      final day = parts[2].trim().split(' ')[0];
      return '$year. $month. $day';
    }
    return fullDate.split(' ')[0];
  }

  List<dynamic> _groupByDate(List<MatchRecord> records) {
    final items = <dynamic>[];
    String? lastDate;
    int dateCount = 0;
    int headerIdx = -1;

    for (final record in records) {
      final dateKey = _extractDate(record.date);
      if (dateKey != lastDate) {
        if (headerIdx >= 0) {
          items[headerIdx] = '${items[headerIdx]}||$dateCount';
        }
        lastDate = dateKey;
        headerIdx = items.length;
        dateCount = 0;
        items.add(dateKey);
      }
      dateCount++;
      items.add(record);
    }
    if (headerIdx >= 0) {
      items[headerIdx] = '${items[headerIdx]}||$dateCount';
    }
    return items;
  }

  Future<bool> _confirmDelete(
      BuildContext context, MatchRecord record) async {
    final winnerText = record.winner2.isEmpty
        ? record.winner1
        : '${record.winner1} & ${record.winner2}';
    final loserText = record.loser2.isEmpty
        ? record.loser1
        : '${record.loser1} & ${record.loser2}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('기록 삭제'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.date,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('승: $winnerText'),
            Text('패: $loserText'),
            const SizedBox(height: 16),
            const Text('이 기록을 삭제하시겠습니까?',
                style: TextStyle(fontWeight: FontWeight.w500)),
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    if (!context.mounted) return false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 24),
              Expanded(
                child: Text(
                  '삭제 처리 중…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await _sheetsService.deleteMatchRecord(record.rowIndex);
      await _refresh();
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('기록이 삭제되었습니다'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return false;
    } finally {
      if (context.mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 20,
              right: 20,
              bottom: 16,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
            ),
            child: Row(
              children: [
                const Text(
                  '전체 기록',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MatchRecord>>(
              future: _matchRecords,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            '오류 발생: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final records = snapshot.data!;

                if (records.isEmpty) {
                  return const Center(child: Text('경기 기록이 없습니다.'));
                }

                final reversedRecords = records.reversed.toList();
                final grouped = _groupByDate(reversedRecords);

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: grouped.length,
                    itemBuilder: (context, index) {
                      final item = grouped[index];
                      if (item is String) {
                        return _DateHeader(date: item);
                      }
                      final record = item as MatchRecord;
                      return Dismissible(
                        key: ValueKey(
                            '${record.rowIndex}_${record.date}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete,
                              color: Colors.white),
                        ),
                        confirmDismiss: (_) =>
                            _confirmDelete(context, record),
                        onDismissed: (_) {},
                        child: _MatchCard(record: record),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String date;

  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final parts = date.split('||');
    final dateText = parts[0];
    final count = parts.length > 1 ? parts[1] : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
      child: Row(
        children: [
          Text(
            dateText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          if (count.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count경기',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
          const Spacer(),
          Expanded(
            child: Divider(color: Colors.grey.shade300, height: 1),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchRecord record;

  const _MatchCard({required this.record});

  String _extractTime(String fullDate) {
    final idx = fullDate.indexOf('오');
    if (idx >= 0) return fullDate.substring(idx).trim();
    final parts = fullDate.split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : fullDate;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _extractTime(record.date),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (record.isInProgress) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      '진행중',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: record.isInProgress
                          ? Colors.grey.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: record.isInProgress
                              ? Colors.grey.shade300
                              : Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          record.isInProgress ? 'A팀' : '승',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: record.isInProgress
                                ? Colors.grey.shade600
                                : Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.winner2.isEmpty
                              ? record.winner1
                              : '${record.winner1} & ${record.winner2}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: record.isInProgress
                          ? Colors.grey.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: record.isInProgress
                              ? Colors.grey.shade300
                              : Colors.red.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          record.isInProgress ? 'B팀' : '패',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: record.isInProgress
                                ? Colors.grey.shade600
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.loser2.isEmpty
                              ? record.loser1
                              : '${record.loser1} & ${record.loser2}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
