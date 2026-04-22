class HanmadiComment {
  final String postId;
  final String createdAt;
  final String author;
  final String body;

  const HanmadiComment({
    required this.postId,
    required this.createdAt,
    required this.author,
    required this.body,
  });

  factory HanmadiComment.fromSheetRow(List<dynamic> row) {
    return HanmadiComment(
      postId: row.isNotEmpty ? row[0].toString().trim() : '',
      createdAt: row.length > 1 ? row[1].toString().trim() : '',
      author: row.length > 2 ? row[2].toString().trim() : '',
      body: row.length > 3 ? row[3].toString().trim() : '',
    );
  }
}

class HanmadiPost {
  final String id;
  final String createdAt;
  final String author;
  final String body;
  final int likeCount;
  final int dislikeCount;
  final List<HanmadiComment> comments;

  const HanmadiPost({
    required this.id,
    required this.createdAt,
    required this.author,
    required this.body,
    required this.likeCount,
    required this.dislikeCount,
    this.comments = const [],
  });

  HanmadiPost copyWith({List<HanmadiComment>? comments}) {
    return HanmadiPost(
      id: id,
      createdAt: createdAt,
      author: author,
      body: body,
      likeCount: likeCount,
      dislikeCount: dislikeCount,
      comments: comments ?? this.comments,
    );
  }

  factory HanmadiPost.fromSheetRow(List<dynamic> row) {
    return HanmadiPost(
      id: row.isNotEmpty ? row[0].toString().trim() : '',
      createdAt: row.length > 1 ? row[1].toString().trim() : '',
      author: row.length > 2 ? row[2].toString().trim() : '',
      body: row.length > 3 ? row[3].toString().trim() : '',
      likeCount: row.length > 4 ? int.tryParse(row[4].toString()) ?? 0 : 0,
      dislikeCount: row.length > 5 ? int.tryParse(row[5].toString()) ?? 0 : 0,
    );
  }
}
