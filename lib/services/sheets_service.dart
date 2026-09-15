import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hanmadi_post.dart';
import '../models/match_record.dart';
import '../models/player_stats.dart';
import '../models/sheet_workspace.dart';

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
  /// 10전 이상 전 조합, 승률 내림차순 (전체 순위)
  final List<DuoRecord> allRankedDuos;
  /// 집계에 사용한 기록 (파트너 세부 전적 계산용)
  final List<MatchRecord> records;

  DuoData({
    required this.bestDuos,
    required this.worstDuos,
    required this.mostPlayedDuos,
    required this.leastPlayedDuos,
    this.allRankedDuos = const [],
    this.records = const [],
  });
}

/// 특정 두 선수가 한 팀일 때의 세부 전적 (시트 '파트너 전적' 탭과 동일)
class DuoDetail {
  final int wins;
  final int losses;
  /// 상대 조합별 전적 (team = "상대1 & 상대2")
  final List<DuoRecord> vsPairs;
  /// 상대 개인별 전적 (team = 상대 이름)
  final List<DuoRecord> vsPlayers;

  DuoDetail({
    required this.wins,
    required this.losses,
    required this.vsPairs,
    required this.vsPlayers,
  });

  int get total => wins + losses;
}

class DailyScore {
  final String date;
  final Map<String, int> scores;

  DailyScore({required this.date, required this.scores});
}

class SheetsService {
  // ── 대상 시트 선택 ──
  /// 기본 시트. 앱을 처음 켜면 이 시트를 바라본다.
  static const SheetWorkspace defaultWorkspace = SheetWorkspace(
    name: '슈터탁구본부',
    spreadsheetId: '1dtlIlaNiLkh8s6-qTApfCTuNqGAR2NbMKGP1EsM_CS0',
    appsScriptUrl:
        'https://script.google.com/macros/s/AKfycbwQy-bSMDNm2SdxZAmQnhzlVWX3rliHQjl7ATKRjQTlmp0FjmYMyfWwhhFFUuiQLjNZ/exec',
  );

  static const _workspacesKey = 'sheet_workspaces_v1';
  static const _activeWorkspaceKey = 'sheet_workspace_active_v1';
  static SheetWorkspace _current = defaultWorkspace;

  /// 현재 선택된 시트
  static SheetWorkspace get currentWorkspace => _current;
  static String get _spreadsheetId => _current.spreadsheetId;
  static String get _appsScriptUrl => _current.appsScriptUrl;

  /// Apps Script 요청 URL. 스크립트가 여러 시트를 처리할 수 있도록
  /// 현재 시트 ID를 항상 함께 보낸다 (스크립트가 무시해도 무방).
  static Uri _scriptUri(Map<String, String> params) =>
      Uri.parse(_appsScriptUrl).replace(
        queryParameters: {'sheetId': _spreadsheetId, ...params},
      );

  /// 앱 시작 시 마지막으로 선택한 시트 복원
  static Future<void> loadActiveWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeWorkspaceKey);
    if (id == null) return;
    final list = await loadWorkspaces();
    _current = list.firstWhere(
      (w) => w.spreadsheetId == id,
      orElse: () => defaultWorkspace,
    );
  }

  /// 저장된 시트 목록 (기본 시트는 항상 첫 번째)
  static Future<List<SheetWorkspace>> loadWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workspacesKey);
    final saved = <SheetWorkspace>[];
    if (raw != null) {
      try {
        for (final e in json.decode(raw) as List) {
          saved.add(SheetWorkspace.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    return [
      defaultWorkspace,
      ...saved.where(
          (w) => w.spreadsheetId != defaultWorkspace.spreadsheetId),
    ];
  }

  /// 시트 추가(같은 ID면 덮어씀)
  static Future<void> saveWorkspace(SheetWorkspace ws) async {
    final list = (await loadWorkspaces())
        .where((w) => w.spreadsheetId != defaultWorkspace.spreadsheetId)
        .where((w) => w.spreadsheetId != ws.spreadsheetId)
        .toList()
      ..add(ws);
    await _storeWorkspaces(list);
    if (_current.spreadsheetId == ws.spreadsheetId) _current = ws;
  }

  static Future<void> deleteWorkspace(SheetWorkspace ws) async {
    final list = (await loadWorkspaces())
        .where((w) => w.spreadsheetId != defaultWorkspace.spreadsheetId)
        .where((w) => w.spreadsheetId != ws.spreadsheetId)
        .toList();
    await _storeWorkspaces(list);
  }

  static Future<void> _storeWorkspaces(List<SheetWorkspace> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _workspacesKey,
      json.encode([for (final w in list) w.toJson()]),
    );
  }

  /// 시트 전환. 캐시를 비우고, 선택 선수는 시트별로 따로 기억한다.
  /// 반환값: 새 시트에서 이전에 고른 선수가 있으면 true (선수 선택 화면을 건너뜀)
  static Future<bool> switchWorkspace(SheetWorkspace ws) async {
    final prefs = await SharedPreferences.getInstance();

    // 현재 시트의 선택 선수를 시트별 키에 보관
    final currentPlayer = prefs.getString('selected_player');
    if (currentPlayer != null) {
      await prefs.setString(
          'selected_player_${_current.spreadsheetId}', currentPlayer);
    }

    _current = ws;
    await prefs.setString(_activeWorkspaceKey, ws.spreadsheetId);

    // 시트 종속 상태 초기화
    _recordsMem = null;
    _recordsInFlight = null;
    _archivedRecordsCache = null;
    _archivedSeasons = null;
    _inFlight.clear();
    for (final k in [
      'prev_rank_order',
      'prev_rankings',
      'prev_rankings_date',
      'rank_change_banner',
      'rank_change_banner_date',
    ]) {
      await prefs.remove(k);
    }

    final saved = prefs.getString('selected_player_${ws.spreadsheetId}');
    if (saved != null && saved.isNotEmpty) {
      await prefs.setString('selected_player', saved);
      return true;
    }
    await prefs.remove('selected_player');
    return false;
  }

  static const String _apiKey = 'AIzaSyD-ZvGbSZv8MkzE8eNQCr6SOwkkMHCEO30';

  static const String _baseUrl =
      'https://sheets.googleapis.com/v4/spreadsheets';

  /// 새 선수를 메인 시트에 등록
  Future<void> addPlayer(String name) async {
    final url = _scriptUri({
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
    final url = _scriptUri({
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

  /// 같은 범위를 동시에 여러 곳에서 요청하면 HTTP 1회로 합침.
  /// (결과를 저장해두는 캐시가 아니라, 응답이 오면 바로 지워짐 — 항상 시트 최신값)
  static final Map<String, Future<List<dynamic>>> _inFlight = {};

  Future<List<dynamic>> _fetchSheetValues(
      String sheetName, String range) {
    final key = '$sheetName!$range';
    return _inFlight[key] ??= _fetchSheetValuesNow(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<List<dynamic>> _fetchSheetValuesNow(String fullRange) async {
    final encodedRange = Uri.encodeComponent(fullRange);
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

  static String get _recordsCacheKey => 'records_cache_v1_$_spreadsheetId';
  /// 오늘 포함 최근 며칠은 항상 시트에서 읽을지 (그 이전 기록만 로컬 캐시 사용)
  static const _freshDays = 3;
  static List<MatchRecord>? _recordsMem;
  static Future<List<MatchRecord>>? _recordsInFlight;

  /// 기록DB 조회. 항상 시트를 읽지만, 수정/추가/삭제는 최근 며칠 안에만 일어난다는
  /// 전제로 그 이전 기록은 로컬 캐시를 쓰고 **최근 [_freshDays]일 첫 행부터만** 요청한다.
  /// 경계 행(그 직전 행) 1개를 함께 받아 캐시와 다르면 전체를 다시 읽는다.
  /// [force]가 true면 캐시를 무시하고 전체 조회 (당겨서 새로고침용).
  Future<List<MatchRecord>> fetchMatchRecords({bool force = false}) {
    if (force) return _fetchAllRecords();
    return _recordsInFlight ??= _fetchRecordsIncremental().whenComplete(() {
      _recordsInFlight = null;
    });
  }

  Future<List<MatchRecord>> _fetchAllRecords() async {
    final rows = await _fetchSheetValues('기록DB', 'A2:E');
    final records = <MatchRecord>[];
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.isEmpty || row[0].toString().isEmpty) continue;
      records.add(MatchRecord.fromSheetRow(row, i + 2));
    }
    await _saveRecordsCache(records);
    return records;
  }

  Future<List<MatchRecord>> _fetchRecordsIncremental() async {
    final cached = _recordsMem ?? await _loadRecordsCache();
    if (cached == null || cached.isEmpty) return _fetchAllRecords();

    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: _freshDays - 1));
    var firstFresh = cached.length;
    for (int i = cached.length - 1; i >= 0; i--) {
      final d = _recordDay(cached[i].date);
      if (d == null || !d.isBefore(cutoff)) {
        firstFresh = i;
      } else {
        break;
      }
    }
    if (firstFresh == 0) return _fetchAllRecords();

    // 경계 행(캐시의 firstFresh-1 번째 = 시트 firstFresh+1 행)부터 끝까지
    final boundaryRow = firstFresh + 1;
    final rows = await _fetchSheetValues('기록DB', 'A$boundaryRow:E');
    if (rows.isEmpty || !_sameRow(rows[0] as List, cached[firstFresh - 1])) {
      return _fetchAllRecords();
    }

    final records = cached.sublist(0, firstFresh);
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.isEmpty || row[0].toString().isEmpty) continue;
      records.add(MatchRecord.fromSheetRow(row, boundaryRow + i));
    }
    await _saveRecordsCache(records);
    return records;
  }

  /// "2026. 9. 15 오후 1:04:54" → 날짜 부분만 (시각 제외). 파싱 실패 시 null.
  DateTime? _recordDay(String date) {
    final p = date.split('.');
    if (p.length < 3) return null;
    final y = int.tryParse(p[0].trim());
    final m = int.tryParse(p[1].trim());
    final d = int.tryParse(p[2].trim().split(' ')[0]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  bool _sameRow(List<dynamic> row, MatchRecord r) {
    String cell(int i) => i < row.length ? row[i].toString().trim() : '';
    return cell(0) == r.date.trim() &&
        cell(1) == r.winner1.trim() &&
        cell(2) == r.winner2.trim() &&
        cell(3) == r.loser1.trim() &&
        cell(4) == r.loser2.trim();
  }

  Future<List<MatchRecord>?> _loadRecordsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recordsCacheKey);
      if (raw == null) return null;
      final rows = json.decode(raw) as List;
      return _recordsMem = [
        for (int i = 0; i < rows.length; i++)
          MatchRecord.fromSheetRow(rows[i] as List, i + 2),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecordsCache(List<MatchRecord> records) async {
    final prev = _recordsMem;
    _recordsMem = records;
    // 마지막 행까지 같으면 디스크에 다시 쓰지 않음
    if (prev != null &&
        prev.length == records.length &&
        (records.isEmpty || _sameRow(records.last.toRow(), prev.last))) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recordsCacheKey,
        json.encode([for (final r in records) r.toRow()]),
      );
    } catch (_) {}
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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

  /// 기록을 순서대로 훑어 선수별 승·패·현재 연승(양수)/연패(음수)·최장 연승·최장 연패 집계.
  /// 연승/연패는 날짜가 바뀌어도 이어진다.
  ({
    Map<String, int> wins,
    Map<String, int> losses,
    Map<String, int> streak,
    Map<String, int> maxWin,
    Map<String, int> maxLose,
  }) _tallyRecords(List<MatchRecord> records) {
    final wins = <String, int>{};
    final losses = <String, int>{};
    final streak = <String, int>{};
    final maxWin = <String, int>{};
    final maxLose = <String, int>{};

    for (final record in records) {
      if (record.isInProgress) continue;
      for (final name in [record.winner1, record.winner2]) {
        if (name.isEmpty) continue;
        wins[name] = (wins[name] ?? 0) + 1;
        final prev = streak[name] ?? 0;
        final s = prev > 0 ? prev + 1 : 1;
        streak[name] = s;
        if (s > (maxWin[name] ?? 0)) maxWin[name] = s;
      }
      for (final name in [record.loser1, record.loser2]) {
        if (name.isEmpty) continue;
        losses[name] = (losses[name] ?? 0) + 1;
        final prev = streak[name] ?? 0;
        final s = prev < 0 ? prev - 1 : -1;
        streak[name] = s;
        if (-s > (maxLose[name] ?? 0)) maxLose[name] = -s;
      }
    }
    return (
      wins: wins,
      losses: losses,
      streak: streak,
      maxWin: maxWin,
      maxLose: maxLose,
    );
  }

  /// 기록만으로 한 선수의 전적·연승 계산 (승점 등 시트 값 없음). 전체 시즌 세부 전적용.
  PlayerStats buildPlayerStatsFromRecords(
      List<MatchRecord> records, String name) {
    final t = _tallyRecords(records);
    final wins = t.wins[name] ?? 0;
    final losses = t.losses[name] ?? 0;
    final games = wins + losses;
    final total = records.where((r) => !r.isInProgress).length;
    return PlayerStats(
      name: name,
      totalGames: games,
      wins: wins,
      losses: losses,
      winRate: games > 0 ? wins / games * 100 : 0,
      participationRate: total > 0 ? games / total * 100 : 0,
      currentStreak: t.streak[name] ?? 0,
      maxWinStreak: t.maxWin[name] ?? 0,
      maxLoseStreak: t.maxLose[name] ?? 0,
    );
  }

  Future<List<PlayerStats>> fetchPlayerStats() async {
    final results = await Future.wait([
      _fetchSheetValues('메인', 'F1:J'),
      fetchMatchRecords(),
    ]);

    final mainRows = results[0];
    final records = results[1] as List<MatchRecord>;
    final tally = _tallyRecords(records);
    final winsMap = tally.wins;
    final lossesMap = tally.losses;
    final streakMap = tally.streak;
    final maxWinMap = tally.maxWin;
    final maxLoseMap = tally.maxLose;

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

  /// 2vs2만: 승팀·패팀 각각의 듀오 조합 키 (이름 정렬 후 "A & B")
  static String _canonicalDuoTeam(String a, String b) {
    final names = [a.trim(), b.trim()]..sort();
    return '${names[0]} & ${names[1]}';
  }

  /// 1대1(양쪽 모두 단식)은 제외하고, 기록DB에서 2vs2 경기만 집계해
  /// 함께 출전 횟수 TOP 3 / WORST 3용 [DuoRecord] 생성.
  ({List<DuoRecord> all, List<DuoRecord> mostPlayed, List<DuoRecord> leastPlayed})
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

    return (all: list, mostPlayed: mostPlayed, leastPlayed: leastPlayed);
  }

  /// 현재 시즌 + 아카이브 시즌 전체 기록으로 듀오 분석.
  Future<DuoData> fetchDuoDataAllSeasons() async {
    final results = await Future.wait([
      fetchMatchRecords(),
      fetchArchivedRecords(),
    ]);
    return _buildDuoData([...results[0], ...results[1]]);
  }

  /// 베스트/워스트(10전 이상, 승률순) + 듀오 횟수 TOP/WORST. 2vs2만 집계.
  DuoData _buildDuoData(List<MatchRecord> records) {
    final counts = _duoPlayCountsDoublesOnly(records);

    double rate(DuoRecord r) {
      final total = r.wins + r.losses;
      return total == 0 ? 0 : r.wins / total;
    }

    final qualified =
        counts.all.where((r) => (r.totalGames ?? 0) >= 10).toList();
    final best = List<DuoRecord>.from(qualified)
      ..sort((a, b) {
        final c = rate(b).compareTo(rate(a));
        if (c != 0) return c;
        return (b.totalGames ?? 0).compareTo(a.totalGames ?? 0);
      });
    final worst = List<DuoRecord>.from(qualified)
      ..sort((a, b) {
        final c = rate(a).compareTo(rate(b));
        if (c != 0) return c;
        return (b.totalGames ?? 0).compareTo(a.totalGames ?? 0);
      });

    return DuoData(
      bestDuos: best.take(3).toList(),
      worstDuos: worst.take(3).toList(),
      mostPlayedDuos: counts.mostPlayed,
      leastPlayedDuos: counts.leastPlayed,
      allRankedDuos: best,
      records: records,
    );
  }

  /// [a]·[b]가 한 팀이었던 2vs2 경기만으로 상대 조합별 / 상대 개인별 전적 계산.
  DuoDetail buildDuoDetail(List<MatchRecord> records, String a, String b) {
    final me = _canonicalDuoTeam(a, b);
    var wins = 0;
    var losses = 0;
    final pairAgg = <String, ({int wins, int losses})>{};
    final playerAgg = <String, ({int wins, int losses})>{};

    void add(Map<String, ({int wins, int losses})> agg, String key, bool won) {
      final e = agg[key] ?? (wins: 0, losses: 0);
      agg[key] = won
          ? (wins: e.wins + 1, losses: e.losses)
          : (wins: e.wins, losses: e.losses + 1);
    }

    for (final r in records) {
      if (r.isInProgress) continue;
      final w1 = r.winner1.trim();
      final w2 = r.winner2.trim();
      final l1 = r.loser1.trim();
      final l2 = r.loser2.trim();
      if (w1.isEmpty || w2.isEmpty || l1.isEmpty || l2.isEmpty) continue;

      final bool won;
      final String o1;
      final String o2;
      if (_canonicalDuoTeam(w1, w2) == me) {
        won = true;
        o1 = l1;
        o2 = l2;
      } else if (_canonicalDuoTeam(l1, l2) == me) {
        won = false;
        o1 = w1;
        o2 = w2;
      } else {
        continue;
      }

      if (won) {
        wins++;
      } else {
        losses++;
      }
      add(pairAgg, _canonicalDuoTeam(o1, o2), won);
      add(playerAgg, o1, won);
      add(playerAgg, o2, won);
    }

    List<DuoRecord> toSorted(Map<String, ({int wins, int losses})> agg) {
      final list = agg.entries.map((e) {
        final total = e.value.wins + e.value.losses;
        return DuoRecord(
          team: e.key,
          wins: e.value.wins,
          losses: e.value.losses,
          winRate: '${(e.value.wins / total * 100).toStringAsFixed(1)}%',
          totalGames: total,
        );
      }).toList();
      list.sort((x, y) {
        final rx = x.wins / (x.totalGames ?? 1);
        final ry = y.wins / (y.totalGames ?? 1);
        final c = ry.compareTo(rx);
        if (c != 0) return c;
        final t = (y.totalGames ?? 0).compareTo(x.totalGames ?? 0);
        if (t != 0) return t;
        return x.team.compareTo(y.team);
      });
      return list;
    }

    return DuoDetail(
      wins: wins,
      losses: losses,
      vsPairs: toSorted(pairAgg),
      vsPlayers: toSorted(playerAgg),
    );
  }

  /// 현재 시즌 기록DB의 2vs2 경기만으로 듀오 분석.
  /// (메인 시트 수식은 1대1 기록을 듀오로 잡고 구간 경계가 없어 사용하지 않음)
  Future<DuoData> fetchDuoData() async {
    return _buildDuoData(await fetchMatchRecords());
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
    final url = _scriptUri({
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
      _archivedRecordsCache = null;
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

  /// 아카이브된 전 시즌 기록(통합). 아카이브는 바뀌지 않으므로 폰에 저장해두고
  /// 바로 쓰고, 시즌 목록만 백그라운드로 확인해 새 시즌이 생겼을 때만 다시 읽는다.
  /// 실패 시 빈 목록(보조 데이터라 화면을 막지 않음).
  static String get _archiveCacheKey => 'archive_cache_v1_$_spreadsheetId';
  static List<MatchRecord>? _archivedRecordsCache;
  static List<String>? _archivedSeasons;

  Future<List<MatchRecord>> fetchArchivedRecords() async {
    if (_archivedRecordsCache != null) return _archivedRecordsCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_archiveCacheKey);
      if (raw != null) {
        final data = json.decode(raw) as Map<String, dynamic>;
        _archivedSeasons = (data['seasons'] as List).cast<String>();
        final rows = data['rows'] as List;
        _archivedRecordsCache = [
          for (int i = 0; i < rows.length; i++)
            MatchRecord.fromSheetRow(rows[i] as List, i + 2),
        ];
        // 시즌 목록이 달라졌으면(새 아카이브) 다음 조회부터 새 데이터
        unawaited(_refreshArchiveIfSeasonsChanged());
        return _archivedRecordsCache!;
      }
      return await _fetchAndStoreArchive();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshArchiveIfSeasonsChanged() async {
    try {
      final seasons = await fetchAvailableSeasons();
      if (seasons.isEmpty) return;
      final same = _archivedSeasons != null &&
          seasons.length == _archivedSeasons!.length &&
          seasons.every(_archivedSeasons!.contains);
      if (!same) await _fetchAndStoreArchive();
    } catch (_) {}
  }

  Future<List<MatchRecord>> _fetchAndStoreArchive() async {
    final seasons = await fetchAvailableSeasons();
    final lists = await Future.wait(seasons.map(fetchSeasonRecords));
    final merged = [for (final l in lists) ...l];
    _archivedSeasons = seasons;
    _archivedRecordsCache = merged;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _archiveCacheKey,
        json.encode({
          'seasons': seasons,
          'rows': [for (final r in merged) r.toRow()],
        }),
      );
    } catch (_) {}
    return merged;
  }

  /// 아카이브 + 현재 시즌 기록을 날짜순으로 합침 (연승 계산 등 순서가 중요한 곳용)
  Future<List<MatchRecord>> fetchAllSeasonRecords() async {
    final results = await Future.wait([
      fetchArchivedRecords(),
      fetchMatchRecords(),
    ]);
    final merged = [...results[0], ...results[1]];
    final indexed = List.generate(merged.length, (i) => i);
    indexed.sort((a, b) {
      final da = _recordDay(merged[a].date);
      final db = _recordDay(merged[b].date);
      if (da != null && db != null) {
        final c = da.compareTo(db);
        if (c != 0) return c;
      }
      return a.compareTo(b);
    });
    return [for (final i in indexed) merged[i]];
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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
    final url = _scriptUri({
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
