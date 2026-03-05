import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/match_record.dart';
import '../models/player_stats.dart';

class DuoRecord {
  final String team;
  final int wins;
  final int losses;
  final String winRate;
  final int? totalGames;

  DuoRecord({
    required this.team,
    required this.wins,
    required this.losses,
    required this.winRate,
    this.totalGames,
  });
}

class DuoData {
  final List<DuoRecord> bestDuos;
  final List<DuoRecord> worstDuos;
  final List<DuoRecord> mostPlayedDuos;
  final List<DuoRecord> leastPlayedDuos;

  DuoData({
    required this.bestDuos,
    required this.worstDuos,
    required this.mostPlayedDuos,
    required this.leastPlayedDuos,
  });
}

class DailyScore {
  final String date;
  final Map<String, int> scores;

  DailyScore({required this.date, required this.scores});
}

class SheetsService {
  static const String _spreadsheetId =
      '1dtlIlaNiLkh8s6-qTApfCTuNqGAR2NbMKGP1EsM_CS0';

  static const String _apiKey = 'AIzaSyD-ZvGbSZv8MkzE8eNQCr6SOwkkMHCEO30';

  static const String _baseUrl =
      'https://sheets.googleapis.com/v4/spreadsheets';

  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbyV71nXAFzTY1_Sj-_DnOuCJq1tx1HrrHpRNmtaWZ5R4EITmAXldCCvx4RcFNyuYQEUQQ/exec';

  /// 경기 결과를 Google Apps Script를 통해 기록DB에 저장 (1v1, 2v2 모두 지원)
  Future<void> submitMatchResult({
    required String winner1,
    String winner2 = '',
    required String loser1,
    String loser2 = '',
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'winner1': winner1,
      'winner2': winner2,
      'loser1': loser1,
      'loser2': loser2,
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('기록 저장 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('기록 저장 실패: HTTP ${response.statusCode}');
    }
  }

  Future<List<dynamic>> _fetchSheetValues(
      String sheetName, String range) async {
    final encodedRange = Uri.encodeComponent('$sheetName!$range');
    final url = Uri.parse(
      '$_baseUrl/$_spreadsheetId/values/$encodedRange?key=$_apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['values'] ?? [];
    } else {
      throw Exception(
        '데이터를 불러오는데 실패했습니다: ${response.statusCode}\n${response.body}',
      );
    }
  }

  Future<List<MatchRecord>> fetchMatchRecords() async {
    final rows = await _fetchSheetValues('기록DB', 'A2:E');
    final records = <MatchRecord>[];
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.isEmpty || row[0].toString().isEmpty) continue;
      records.add(MatchRecord.fromSheetRow(row, i + 2));
    }
    return records;
  }

  /// '진행중게임' 시트에서 진행중 경기 목록 조회
  Future<List<MatchRecord>> fetchInProgressGames() async {
    try {
      final rows = await _fetchSheetValues('진행중게임', 'A2:E');
      final records = <MatchRecord>[];
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i] as List;
        if (row.isEmpty || row[0].toString().isEmpty) continue;
        records.add(MatchRecord(
          rowIndex: i + 2,
          date: row[0].toString(),
          winner1: row.length > 1 ? row[1].toString() : '',
          winner2: row.length > 2 ? row[2].toString() : '',
          loser1: row.length > 3 ? row[3].toString() : '',
          loser2: row.length > 4 ? row[4].toString() : '',
          status: '진행중',
        ));
      }
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 진행중 경기를 '진행중게임' 시트에 기록
  Future<int> startGame({
    required String teamA1,
    String teamA2 = '',
    required String teamB1,
    String teamB2 = '',
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'start',
      'teamA1': teamA1,
      'teamA2': teamA2,
      'teamB1': teamB1,
      'teamB2': teamB2,
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] == 'success') {
        return data['row'] as int;
      }
      throw Exception('경기 시작 기록 실패: ${data['error'] ?? '알 수 없는 오류'}');
    }
    throw Exception('경기 시작 기록 실패: HTTP ${response.statusCode}');
  }

  /// 진행중 경기를 완료: '진행중게임'에서 삭제 후 '기록DB'에 기록
  Future<void> completeGame({
    required int rowIndex,
    required String winner1,
    String winner2 = '',
    required String loser1,
    String loser2 = '',
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'complete',
      'row': rowIndex.toString(),
      'winner1': winner1,
      'winner2': winner2,
      'loser1': loser1,
      'loser2': loser2,
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('경기 완료 처리 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('경기 완료 처리 실패: HTTP ${response.statusCode}');
    }
  }

  /// 진행중 경기 취소: '진행중게임' 시트에서 삭제
  Future<void> cancelInProgressGame(int rowIndex) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'cancel_game',
      'row': rowIndex.toString(),
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('경기 취소 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('경기 취소 실패: HTTP ${response.statusCode}');
    }
  }

  /// Apps Script를 통해 기록DB에서 특정 행 삭제
  Future<void> deleteMatchRecord(int rowIndex) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'delete',
      'row': rowIndex.toString(),
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('삭제 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('삭제 실패: HTTP ${response.statusCode}');
    }
  }

  Future<List<PlayerStats>> fetchPlayerStats() async {
    final results = await Future.wait([
      _fetchSheetValues('메인', 'F1:J'),
      fetchMatchRecords(),
    ]);

    final mainRows = results[0];
    final records = results[1] as List<MatchRecord>;

    final Map<String, int> winsMap = {};
    final Map<String, int> lossesMap = {};
    final Map<String, int> streakMap = {};
    final Map<String, int> maxWinMap = {};
    final Map<String, int> maxLoseMap = {};
    final Map<String, int> tempStreakMap = {};
    String lastDateKey = '';

    for (final record in records) {
      final dateKey = _extractDateKey(record.date);
      if (dateKey != lastDateKey) {
        tempStreakMap.clear();
        lastDateKey = dateKey;
      }

      final winners = <String>{};
      final losers = <String>{};
      for (final name in [record.winner1, record.winner2]) {
        if (name.isEmpty) continue;
        winsMap[name] = (winsMap[name] ?? 0) + 1;
        winners.add(name);
      }
      for (final name in [record.loser1, record.loser2]) {
        if (name.isEmpty) continue;
        lossesMap[name] = (lossesMap[name] ?? 0) + 1;
        losers.add(name);
      }
      for (final name in winners) {
        final prev = tempStreakMap[name] ?? 0;
        final streak = prev > 0 ? prev + 1 : 1;
        tempStreakMap[name] = streak;
        maxWinMap[name] = (maxWinMap[name] ?? 0) > streak
            ? maxWinMap[name]!
            : streak;
      }
      for (final name in losers) {
        final prev = tempStreakMap[name] ?? 0;
        final streak = prev < 0 ? prev - 1 : -1;
        tempStreakMap[name] = streak;
        final absStreak = streak.abs();
        maxLoseMap[name] = (maxLoseMap[name] ?? 0) > absStreak
            ? maxLoseMap[name]!
            : absStreak;
      }
    }
    streakMap.addAll(tempStreakMap);

    final List<PlayerStats> stats = [];

    for (int i = 1; i < mainRows.length; i++) {
      final row = mainRows[i] as List;
      if (row.length < 4) continue;

      final totalGames = int.tryParse(row[0].toString()) ?? 0;
      final name = row[1].toString().trim();
      if (name.isEmpty) continue;

      final adjustmentPoints = int.tryParse(row[2].toString()) ?? 0;
      final finalScore = int.tryParse(row[3].toString()) ?? 0;
      final recentForm = row.length > 4 ? row[4].toString() : '';

      final wins = winsMap[name] ?? 0;
      final losses = lossesMap[name] ?? 0;
      final games = wins + losses;

      stats.add(PlayerStats(
        name: name,
        totalGames: totalGames,
        wins: wins,
        losses: losses,
        winRate: games > 0 ? wins / games * 100 : 0,
        participationRate:
            records.isNotEmpty ? games / records.length * 100 : 0,
        adjustmentPoints: adjustmentPoints,
        finalScore: finalScore,
        recentForm: recentForm,
        currentStreak: streakMap[name] ?? 0,
        maxWinStreak: maxWinMap[name] ?? 0,
        maxLoseStreak: maxLoseMap[name] ?? 0,
      ));
    }

    stats.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    for (int i = 0; i < stats.length; i++) {
      stats[i].rank = i + 1;
    }

    return stats;
  }

  String _extractDateKey(String fullDate) {
    final parts = fullDate.split('.');
    if (parts.length >= 3) {
      return '${parts[0].trim()}.${parts[1].trim()}.${parts[2].trim().split(' ')[0]}';
    }
    return fullDate.split(' ')[0];
  }

  /// 메인 시트에서 베스트/워스트 듀오 데이터를 파싱
  Future<DuoData> fetchDuoData() async {
    final rows = await _fetchSheetValues('메인', 'K1:U12');

    List<DuoRecord> _parseDuoSection(
        List<dynamic> rows, int startRow, int colOffset,
        {bool hasTotal = false}) {
      final results = <DuoRecord>[];
      for (int i = startRow; i < rows.length; i++) {
        final row = rows[i] as List;
        if (row.length <= colOffset) continue;
        final team = row[colOffset].toString().trim();
        if (team.isEmpty ||
            team.startsWith('팀') ||
            team.startsWith('🏆') ||
            team.startsWith('☠') ||
            team.startsWith('😅') ||
            team.startsWith('파트너')) continue;

        if (hasTotal) {
          if (row.length <= colOffset + 4) continue;
          results.add(DuoRecord(
            team: team,
            totalGames: int.tryParse(row[colOffset + 1].toString()) ?? 0,
            wins: int.tryParse(row[colOffset + 2].toString()) ?? 0,
            losses: int.tryParse(row[colOffset + 3].toString()) ?? 0,
            winRate: row[colOffset + 4].toString(),
          ));
        } else {
          if (row.length <= colOffset + 3) continue;
          results.add(DuoRecord(
            team: team,
            wins: int.tryParse(row[colOffset + 1].toString()) ?? 0,
            losses: int.tryParse(row[colOffset + 2].toString()) ?? 0,
            winRate: row[colOffset + 3].toString(),
          ));
        }
      }
      return results;
    }

    // L~O (index 1~4): 베스트 듀오 rows 2-4, 워스트 듀오 rows 8-10
    // Q~U (index 6~10): 듀오 횟수 TOP rows 2-4, WORST rows 8-10
    return DuoData(
      bestDuos: _parseDuoSection(rows, 2, 1),
      worstDuos: _parseDuoSection(rows, 8, 1),
      mostPlayedDuos: _parseDuoSection(rows, 2, 6, hasTotal: true),
      leastPlayedDuos: _parseDuoSection(rows, 8, 6, hasTotal: true),
    );
  }

  /// 일별점수 시트에서 마지막 2일치를 가져와 당일 점수 변동을 계산
  Future<({String date, List<MapEntry<String, int>> rankings})>
      fetchDailyRanking() async {
    final result = await fetchDailyScores();
    if (result.scores.length < 2) {
      return (date: '', rankings: <MapEntry<String, int>>[]);
    }

    final today = result.scores.last;
    final yesterday = result.scores[result.scores.length - 2];

    final changes = <MapEntry<String, int>>[];
    for (final player in result.players) {
      final todayScore = today.scores[player] ?? 0;
      final yesterdayScore = yesterday.scores[player] ?? 0;
      changes.add(MapEntry(player, todayScore - yesterdayScore));
    }

    changes.sort((a, b) => b.value.compareTo(a.value));
    return (date: today.date, rankings: changes);
  }

  /// 일별점수 시트에서 전체 데이터를 가져옴
  Future<({List<String> players, List<DailyScore> scores})>
      fetchDailyScores() async {
    final rows = await _fetchSheetValues('일별점수', 'A1:Z');

    if (rows.isEmpty) return (players: <String>[], scores: <DailyScore>[]);

    final header = (rows[0] as List).map((e) => e.toString().trim()).toList();
    const invalidNames = {'', '날짜', '#N/A', 'N/A'};
    final allColumns = header.sublist(1);
    final seen = <String>{};
    final validIndices = <int>[];
    final players = <String>[];
    for (int i = 0; i < allColumns.length; i++) {
      final name = allColumns[i];
      if (!invalidNames.contains(name) && seen.add(name)) {
        validIndices.add(i + 1);
        players.add(name);
      }
    }

    const errorValues = {'#VALUE!', '#REF!', '#N/A', '#ERROR!', '#DIV/0!', '#NAME?', '#NULL!'};

    final scores = <DailyScore>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.isEmpty) continue;
      final date = row[0].toString().trim();
      if (date.isEmpty || errorValues.contains(date)) continue;

      final Map<String, int> scoreMap = {};
      bool hasError = false;
      for (int k = 0; k < validIndices.length; k++) {
        final colIdx = validIndices[k];
        if (colIdx < row.length) {
          final val = row[colIdx].toString().trim();
          if (errorValues.contains(val)) {
            hasError = true;
            break;
          }
          scoreMap[players[k]] = int.tryParse(val) ?? 0;
        }
      }
      if (hasError) continue;
      scores.add(DailyScore(date: date, scores: scoreMap));
    }

    return (players: players, scores: scores);
  }
}
