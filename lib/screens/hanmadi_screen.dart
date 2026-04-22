import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hanmadi_post.dart';
import '../services/sheets_service.dart';

class HanmadiScreen extends StatefulWidget {
  const HanmadiScreen({super.key});

  @override
  State<HanmadiScreen> createState() => _HanmadiScreenState();
}

class _HanmadiScreenState extends State<HanmadiScreen> {
  final SheetsService _sheetsService = SheetsService();
  List<HanmadiPost> _posts = [];
  bool _loading = true;
  String? _myName;
  /// 현재 기기에서 선택한 이름 기준, 글별 내 투표(`like` / `dislike`).
  final Map<String, String?> _myVoteByPostId = {};
  final Set<String> _votingPostIds = {};
  final Set<String> _deletingPostIds = {};

  static String _votePrefKey(String voter, String postId) =>
      'hanmadi_myvote_${voter}_$postId';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selected_player');
    final trimmed = raw?.trim();
    if (!mounted) return;
    setState(() {
      _myName =
          (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    });
    await _reloadPosts(withBlockingSpinner: true);
  }

  /// [withBlockingSpinner]: true일 때만 전체 화면 로딩(첫 진입·빈 목록에서 새로고침 등).
  /// 추천/댓글/삭제 후에는 false로 목록만 갱신해 반응이 끊기지 않게 함.
  Future<void> _reloadPosts({bool withBlockingSpinner = false}) async {
    if (withBlockingSpinner && mounted) {
      setState(() => _loading = true);
    }
    try {
      final list = await _sheetsService.fetchHanmadiFeed();
      if (!mounted) return;
      await _refreshVoteCacheForPosts(list);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posts = [];
        _myVoteByPostId.clear();
        _loading = false;
      });
    }
  }

  Future<void> _refreshVoteCacheForPosts(List<HanmadiPost> posts) async {
    final voter = _myName;
    _myVoteByPostId.clear();
    if (voter == null || voter.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final p in posts) {
      _myVoteByPostId[p.id] = prefs.getString(_votePrefKey(voter, p.id));
    }
  }

  Future<void> _setVotePref(String postId, String? vote) async {
    final voter = _myName;
    if (voter == null || voter.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _votePrefKey(voter, postId);
    if (vote == null || vote.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, vote);
    }
  }

  Future<void> _onVote(HanmadiPost post, String nextVote) async {
    final voter = _myName;
    if (voter == null || voter.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('선수 이름이 없습니다. 앱을 다시 시작해 이름을 선택해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_votingPostIds.contains(post.id)) return;
    setState(() => _votingPostIds.add(post.id));

    try {
      await _sheetsService.submitHanmadiVote(
        postId: post.id,
        voter: voter,
        vote: nextVote,
      );
      await _setVotePref(post.id, nextVote == 'none' ? null : nextVote);
      if (!mounted) return;
      setState(() {
        _myVoteByPostId[post.id] =
            nextVote == 'none' ? null : nextVote;
      });
      await _reloadPosts(withBlockingSpinner: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('추천 반영에 실패했습니다. Apps Script에 hanmadi_vote가 있는지 확인해 주세요.\n$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _votingPostIds.remove(post.id));
      }
    }
  }

  bool _isMyPost(HanmadiPost post) {
    final me = _myName;
    if (me == null || me.isEmpty) return false;
    return post.author.trim() == me.trim();
  }

  Future<void> _confirmDeletePost(HanmadiPost post) async {
    final me = _myName;
    if (me == null || me.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('글 삭제'),
        content: const Text('이 글과 댓글·투표 기록이 함께 삭제됩니다. 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deletingPostIds.add(post.id));
    try {
      await _sheetsService.deleteHanmadiPost(postId: post.id, requester: me);
      if (!mounted) return;
      await _setVotePref(post.id, null);
      if (!mounted) return;
      setState(() => _myVoteByPostId.remove(post.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('삭제되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _reloadPosts(withBlockingSpinner: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _openWriteSheet() async {
    final author = _myName;
    if (author == null || author.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이름을 선택한 뒤 글을 쓸 수 있습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bodyController = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '한마디 작성',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '작성자: $author',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: bodyController,
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: '가볍게 남겨 보세요',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final t = bodyController.text.trim();
                            if (t.isEmpty) return;
                            Navigator.pop(ctx, true);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A2E),
                          ),
                          child: const Text('등록'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final text = submitted == true ? bodyController.text.trim() : '';
    bodyController.dispose();

    if (text.isEmpty) return;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('등록 중…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _sheetsService.addHanmadiPost(author: author, body: text);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('등록되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _reloadPosts(withBlockingSpinner: false);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('등록 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openCommentSheet(HanmadiPost post) async {
    final author = _myName;
    if (author == null || author.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이름을 선택한 뒤 댓글을 쓸 수 있습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bodyController = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '댓글',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A2E),
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 300,
                  decoration: InputDecoration(
                    hintText: '댓글을 입력하세요',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (bodyController.text.trim().isEmpty) return;
                          Navigator.pop(ctx, true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A2E),
                        ),
                        child: const Text('등록'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    final text = ok == true ? bodyController.text.trim() : '';
    bodyController.dispose();

    if (text.isEmpty) return;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('등록 중…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _sheetsService.addHanmadiComment(
        postId: post.id,
        author: author,
        body: text,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('댓글이 등록되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _reloadPosts(withBlockingSpinner: false);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('댓글 등록 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildVoteRow(HanmadiPost post) {
    if (_votingPostIds.contains(post.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final current = _myVoteByPostId[post.id];
    return Row(
      children: [
        InkWell(
          onTap: () {
            if (current == 'like') {
              _onVote(post, 'none');
            } else {
              _onVote(post, 'like');
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.thumb_up_alt_outlined,
                  size: 18,
                  color: current == 'like'
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        current == 'like' ? FontWeight.bold : FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {
            if (current == 'dislike') {
              _onVote(post, 'none');
            } else {
              _onVote(post, 'dislike');
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.thumb_down_alt_outlined,
                  size: 18,
                  color: current == 'dislike'
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.dislikeCount}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: current == 'dislike'
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
            '한마디',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
            onPressed: _loading
                ? null
                : () => _reloadPosts(
                      withBlockingSpinner: _posts.isEmpty,
                    ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _openWriteSheet,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('글쓰기'),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _reloadPosts(withBlockingSpinner: false),
                    child: _posts.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.35,
                              ),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: Text(
                                    '아직 글이 없습니다.\n스프레드시트에 시트 이름「한마디」「한마디댓글」을 만들고\nApps Script에 hanmadi_post 등 액션을 연결해 주세요.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                            itemCount: _posts.length,
                            itemBuilder: (context, index) {
                              final post = _posts[index];
                              return Card(
                                color: Colors.white,
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              post.author,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Color(0xFF1A1A2E),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            post.createdAt,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          if (_isMyPost(post)) ...[
                                            const SizedBox(width: 4),
                                            if (_deletingPostIds
                                                .contains(post.id))
                                              const SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: Padding(
                                                  padding: EdgeInsets.all(4),
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              )
                                            else
                                              IconButton(
                                                onPressed: () =>
                                                    _confirmDeletePost(post),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 22,
                                                ),
                                                color: Colors.grey.shade600,
                                                tooltip: '글 삭제',
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 36,
                                                  minHeight: 36,
                                                ),
                                                padding: EdgeInsets.zero,
                                              ),
                                          ],
                                        ],
                                      ),
                                const SizedBox(height: 10),
                                Text(
                                  post.body,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _buildVoteRow(post),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => _openCommentSheet(post),
                                      icon: const Icon(
                                        Icons.chat_bubble_outline,
                                        size: 18,
                                      ),
                                      label: Text(
                                        post.comments.isEmpty
                                            ? '댓글 쓰기'
                                            : '댓글 쓰기 · ${post.comments.length}',
                                      ),
                                    ),
                                  ],
                                ),
                                if (post.comments.isNotEmpty) ...[
                                  Divider(
                                    color: Colors.grey.shade200,
                                    height: 20,
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '댓글 목록',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${post.comments.length}개',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...post.comments.map(
                                    (c) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  c.author,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                    color: Color(0xFF1A1A2E),
                                                  ),
                                                ),
                                              ),
                                              if (c.createdAt.isNotEmpty)
                                                Text(
                                                  c.createdAt,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.grey.shade500,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            c.body,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.35,
                                              color: Colors.grey.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
