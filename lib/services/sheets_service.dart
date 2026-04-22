import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/hanmadi_post.dart';
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
      'https://script.google.com/macros/s/AKfycbwQy-bSMDNm2SdxZAmQnhzlVWX3rliHQjl7ATKRjQTlmp0FjmYMyfWwhhFFUuiQLjNZ/exec';

  /// 새 선수를 메인 시트에 등록
  Future<void> addPlayer(String name) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'add_player',
      'name': name,
    });

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('선수 등록 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('선수 등록 실패: HTTP ${response.statusCode}');
    }
  }

  /// 경기 결과를 Google Apps Script를 통해 기록DB에 저장 (1v1, 2v2 모두 지원)
  Future<void> submitMatchResult({
    required String winner1,
    String winner2 = '',
    required String loser1,
    String loser2 = '',
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'record',
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

    final response = await http.get(url).timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        throw TimeoutException(
          '삭제 요청 시간 초과(45초). 네트워크 또는 Apps Script 응답을 확인하세요.',
        );
      },
    );

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
        maxWinMap[name] =
            (maxWinMap[name] ?? 0) > streak ? maxWinMap[name]! : streak;
      }
      for (final name in losers) {
        final prev = tempStreakMap[name] ?? 0;
        final streak = prev < 0 ? prev - 1 : -1;
        tempStreakMap[name] = streak;
        final absStreak = streak.abs();
        maxLoseMap[name] =
            (maxLoseMap[name] ?? 0) > absStreak ? maxLoseMap[name]! : absStreak;
      }
    }
    streakMap.addAll(tempStreakMap);

    final List<PlayerStats> stats = [];
    final bool hasRecords = records.isNotEmpty;

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
        totalGames: hasRecords ? totalGames : 0,
        wins: wins,
        losses: losses,
        winRate: games > 0 ? wins / games * 100 : 0,
        participationRate: hasRecords ? games / records.length * 100 : 0,
        adjustmentPoints: hasRecords ? adjustmentPoints : 0,
        finalScore: hasRecords ? finalScore : 0,
        recentForm: hasRecords ? recentForm : '',
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

  /// 2vs2만: 승팀·패팀 각각의 듀오 조합 키 (이름 정렬 후 "A & B")
  static String _canonicalDuoTeam(String a, String b) {
    final names = [a.trim(), b.trim()]..sort();
    return '${names[0]} & ${names[1]}';
  }

  /// 1대1(양쪽 모두 단식)은 제외하고, 기록DB에서 2vs2 경기만 집계해
  /// 함께 출전 횟수 TOP 3 / WORST 3용 [DuoRecord] 생성.
  ({List<DuoRecord> mostPlayed, List<DuoRecord> leastPlayed})
      _duoPlayCountsDoublesOnly(List<MatchRecord> records) {
    final agg = <String, ({int wins, int losses})>{};

    for (final r in records) {
      if (r.isInProgress) continue;
      final w1 = r.winner1.trim();
      final w2 = r.winner2.trim();
      final l1 = r.loser1.trim();
      final l2 = r.loser2.trim();
      // 2vs2만: 네 칸 모두 선수명이 있어야 함
      if (w1.isEmpty || w2.isEmpty || l1.isEmpty || l2.isEmpty) continue;

      final winTeam = _canonicalDuoTeam(w1, w2);
      final loseTeam = _canonicalDuoTeam(l1, l2);

      var winEntry = agg[winTeam] ?? (wins: 0, losses: 0);
      winEntry = (wins: winEntry.wins + 1, losses: winEntry.losses);
      agg[winTeam] = winEntry;

      var loseEntry = agg[loseTeam] ?? (wins: 0, losses: 0);
      loseEntry = (wins: loseEntry.wins, losses: loseEntry.losses + 1);
      agg[loseTeam] = loseEntry;
    }

    List<DuoRecord> toRecords() {
      return agg.entries.map((e) {
        final w = e.value.wins;
        final l = e.value.losses;
        final total = w + l;
        final rate =
            total == 0 ? '0.0%' : '${(w / total * 100).toStringAsFixed(1)}%';
        return DuoRecord(
          team: e.key,
          wins: w,
          losses: l,
          winRate: rate,
          totalGames: total,
        );
      }).toList();
    }

    final list = toRecords()
      ..sort((a, b) {
        final t = (b.totalGames ?? 0).compareTo(a.totalGames ?? 0);
        if (t != 0) return t;
        return a.team.compareTo(b.team);
      });

    final mostPlayed = list.take(3).toList();

    final forLeast = List<DuoRecord>.from(list)
      ..sort((a, b) {
        final t = (a.totalGames ?? 0).compareTo(b.totalGames ?? 0);
        if (t != 0) return t;
        return a.team.compareTo(b.team);
      });
    final leastPlayed = forLeast.take(3).toList();

    return (mostPlayed: mostPlayed, leastPlayed: leastPlayed);
  }

  /// 메인 시트에서 베스트/워스트 듀오 데이터를 파싱.
  /// 듀오 횟수 TOP/WORST는 시트가 아닌 기록DB의 2vs2만 반영.
  Future<DuoData> fetchDuoData() async {
    final results = await Future.wait([
      _fetchSheetValues('메인', 'K1:U12'),
      fetchMatchRecords(),
    ]);
    final rows = results[0];
    final matchRecords = results[1] as List<MatchRecord>;

    List<DuoRecord> parseDuoSection(
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

    final counts = _duoPlayCountsDoublesOnly(matchRecords);

    // L~O (index 1~4): 베스트 듀오 rows 2-4, 워스트 듀오 rows 8-10
    // 듀오 횟수 TOP/WORST: 기록DB 2vs2만 사용 (Q~U 시트 구간 무시)
    return DuoData(
      bestDuos: parseDuoSection(rows, 2, 1),
      worstDuos: parseDuoSection(rows, 8, 1),
      mostPlayedDuos: counts.mostPlayed,
      leastPlayedDuos: counts.leastPlayed,
    );
  }

  /// 일별점수 시트에서 당일 점수 변동을 계산
  /// 2일 이상 → 전일 대비 변동, 1일만 → 절대 점수 표시
  Future<({String date, List<MapEntry<String, int>> rankings})>
      fetchDailyRanking() async {
    final result = await fetchDailyScores();
    if (result.scores.isEmpty) {
      return (date: '', rankings: <MapEntry<String, int>>[]);
    }

    final today = result.scores.last;
    final changes = <MapEntry<String, int>>[];

    if (result.scores.length >= 2) {
      final yesterday = result.scores[result.scores.length - 2];
      for (final player in result.players) {
        final todayScore = today.scores[player] ?? 0;
        final yesterdayScore = yesterday.scores[player] ?? 0;
        changes.add(MapEntry(player, todayScore - yesterdayScore));
      }
    } else {
      for (final player in result.players) {
        changes.add(MapEntry(player, today.scores[player] ?? 0));
      }
    }

    changes.sort((a, b) => b.value.compareTo(a.value));
    return (date: today.date, rankings: changes);
  }

  /// 시즌 아카이브: 현재 기록을 별도 시트로 복사하고 현재 시트를 초기화
  Future<void> archiveSeason(String seasonName) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'archive_season',
      'season': seasonName,
    });

    final response = await http.get(url).timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        throw TimeoutException(
          '시즌 아카이브 요청 시간 초과. 네트워크 또는 Apps Script 응답을 확인하세요.',
        );
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception('시즌 아카이브 실패: ${data['error'] ?? '알 수 없는 오류'}');
      }
    } else {
      throw Exception('시즌 아카이브 실패: HTTP ${response.statusCode}');
    }
  }

  /// 스프레드시트의 전체 시트 목록에서 아카이브된 시즌 목록 조회
  Future<List<String>> fetchAvailableSeasons() async {
    final url = Uri.parse(
      '$_baseUrl/$_spreadsheetId?key=$_apiKey&fields=sheets.properties.title',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final data = json.decode(response.body);
    final sheets = data['sheets'] as List? ?? [];
    final seasons = <String>[];
    for (final sheet in sheets) {
      final title = sheet['properties']['title'] as String? ?? '';
      if (title.endsWith('_기록DB')) {
        seasons.add(title.replaceAll('_기록DB', ''));
      }
    }
    return seasons;
  }

  /// 특정 시즌의 기록 조회
  Future<List<MatchRecord>> fetchSeasonRecords(String seasonName) async {
    final sheetName = '${seasonName}_기록DB';
    final rows = await _fetchSheetValues(sheetName, 'A2:E');
    final records = <MatchRecord>[];
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.isEmpty || row[0].toString().isEmpty) continue;
      records.add(MatchRecord.fromSheetRow(row, i + 2));
    }
    return records;
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

    const errorValues = {
      '#VALUE!',
      '#REF!',
      '#N/A',
      '#ERROR!',
      '#DIV/0!',
      '#NAME?',
      '#NULL!'
    };

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

  /// 시트가 없거나 권한 오류 시 빈 목록 (한마디 탭은 선택 기능).
  Future<List<dynamic>> _fetchSheetValuesOrEmpty(
    String sheetName,
    String range,
  ) async {
    try {
      return await _fetchSheetValues(sheetName, range);
    } catch (_) {
      return [];
    }
  }

  /// `한마디` 시트: A=id, B=작성시각(ISO 권장), C=작성자, D=본문, E=추천수, F=비추천수
  /// `한마디댓글` 시트: A=글id, B=작성시각, C=작성자, D=댓글본문
  ///
  /// A1부터 읽음: 헤더 없이 첫 행부터 글만 넣은 GAS와 1행 헤더 방식 모두 대응.
  /// (A2만 읽으면 데이터가 1행뿐일 때 첫 글이 목록에서 빠짐)
  Future<List<HanmadiPost>> fetchHanmadiFeed() async {
    final postRows = await _fetchSheetValuesOrEmpty('한마디', 'A1:F');
    final commentRows = await _fetchSheetValuesOrEmpty('한마디댓글', 'A1:D');

    bool isHanmadiPostHeader(List<dynamic> row) {
      if (row.isEmpty) return true;
      final a = row[0].toString().trim().toLowerCase();
      return a == 'id' || a == '#';
    }

    bool isHanmadiCommentHeader(List<dynamic> row) {
      if (row.isEmpty) return true;
      final a = row[0].toString().trim();
      final lower = a.toLowerCase();
      return lower == 'postid' || lower == 'id' || a == '글id';
    }

    final commentsByPost = <String, List<HanmadiComment>>{};
    for (final raw in commentRows) {
      final row = raw as List<dynamic>;
      if (isHanmadiCommentHeader(row)) continue;
      final c = HanmadiComment.fromSheetRow(row);
      if (c.postId.isEmpty) continue;
      commentsByPost.putIfAbsent(c.postId, () => []).add(c);
    }
    for (final list in commentsByPost.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final posts = <HanmadiPost>[];
    for (final raw in postRows) {
      final row = raw as List<dynamic>;
      if (isHanmadiPostHeader(row)) continue;
      final base = HanmadiPost.fromSheetRow(row);
      if (base.id.isEmpty) continue;
      final merged = commentsByPost[base.id] ?? const <HanmadiComment>[];
      posts.add(base.copyWith(comments: merged));
    }

    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  /// Apps Script에 `action=hanmadi_post` 처리 추가 필요: 행 append 및 id·시각 기록
  Future<void> addHanmadiPost({
    required String author,
    required String body,
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'hanmadi_post',
      'author': author,
      'body': body,
    });

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception(data['error']?.toString() ?? '한마디 등록 실패');
      }
    } else {
      throw Exception('한마디 등록 실패: HTTP ${response.statusCode}');
    }
  }

  /// `action=hanmadi_comment`
  Future<void> addHanmadiComment({
    required String postId,
    required String author,
    required String body,
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'hanmadi_comment',
      'postId': postId,
      'author': author,
      'body': body,
    });

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception(data['error']?.toString() ?? '댓글 등록 실패');
      }
    } else {
      throw Exception('댓글 등록 실패: HTTP ${response.statusCode}');
    }
  }

  /// `action=hanmadi_vote` — vote: `like` | `dislike` | `none`(취소)
  /// GAS에서 동일 postId+voter 조합 중복을 막고 시트의 추천/비추천 수를 갱신하는 것을 권장
  Future<void> submitHanmadiVote({
    required String postId,
    required String voter,
    required String vote,
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'hanmadi_vote',
      'postId': postId,
      'voter': voter,
      'vote': vote,
    });

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception(data['error']?.toString() ?? '추천 반영 실패');
      }
    } else {
      throw Exception('추천 반영 실패: HTTP ${response.statusCode}');
    }
  }

  /// `action=hanmadi_delete_post` — GAS에서 postId 행의 작성자(C열)와 requester 일치 시만 삭제
  Future<void> deleteHanmadiPost({
    required String postId,
    required String requester,
  }) async {
    final url = Uri.parse(_appsScriptUrl).replace(queryParameters: {
      'action': 'hanmadi_delete_post',
      'postId': postId,
      'requester': requester,
    });

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] != 'success') {
        throw Exception(data['error']?.toString() ?? '글 삭제 실패');
      }
    } else {
      throw Exception('글 삭제 실패: HTTP ${response.statusCode}');
    }
  }
}
