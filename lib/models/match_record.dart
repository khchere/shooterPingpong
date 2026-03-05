class MatchRecord {
  final int rowIndex;
  final String date;
  final String winner1;
  final String winner2;
  final String loser1;
  final String loser2;
  final String status;

  MatchRecord({
    required this.rowIndex,
    required this.date,
    required this.winner1,
    required this.winner2,
    required this.loser1,
    required this.loser2,
    this.status = '',
  });

  bool get isInProgress => status == '진행중';

  factory MatchRecord.fromSheetRow(List<dynamic> row, int rowIndex) {
    return MatchRecord(
      rowIndex: rowIndex,
      date: row.isNotEmpty ? row[0].toString() : '',
      winner1: row.length > 1 ? row[1].toString() : '',
      winner2: row.length > 2 ? row[2].toString() : '',
      loser1: row.length > 3 ? row[3].toString() : '',
      loser2: row.length > 4 ? row[4].toString() : '',
      status: row.length > 5 ? row[5].toString().trim() : '',
    );
  }
}
