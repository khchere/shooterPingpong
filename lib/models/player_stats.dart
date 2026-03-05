class PlayerStats {
  final String name;
  final int totalGames;
  final int wins;
  final int losses;
  final double winRate;
  final double participationRate;
  final int adjustmentPoints;
  final int finalScore;
  final String recentForm;
  int rank;
  int currentStreak; // 양수: 연승, 음수: 연패
  int maxWinStreak;
  int maxLoseStreak;

  PlayerStats({
    required this.name,
    required this.totalGames,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.participationRate,
    this.adjustmentPoints = 0,
    this.finalScore = 0,
    this.recentForm = '',
    this.rank = 0,
    this.currentStreak = 0,
    this.maxWinStreak = 0,
    this.maxLoseStreak = 0,
  });
}
