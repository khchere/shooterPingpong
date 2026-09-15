/// 앱이 바라보는 대상 구글 시트 하나의 설정.
/// 시트 구조(메인/기록DB/일별점수 등)와 Apps Script 액션은 동일해야 한다.
class SheetWorkspace {
  final String name;
  final String spreadsheetId;
  final String appsScriptUrl;

  const SheetWorkspace({
    required this.name,
    required this.spreadsheetId,
    required this.appsScriptUrl,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'spreadsheetId': spreadsheetId,
        'appsScriptUrl': appsScriptUrl,
      };

  factory SheetWorkspace.fromJson(Map<String, dynamic> json) => SheetWorkspace(
        name: json['name'] as String? ?? '',
        spreadsheetId: json['spreadsheetId'] as String? ?? '',
        appsScriptUrl: json['appsScriptUrl'] as String? ?? '',
      );

  /// 스프레드시트 URL 또는 ID 문자열에서 ID만 추출
  static String parseSpreadsheetId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9\-_]+)').firstMatch(s);
    return m?.group(1) ?? s;
  }
}
