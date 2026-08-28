import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/search_service.dart';

import 'api_client_test.dart' show Harness;

/// The structured shape api/v1/search.php?format=json emits (raw rank
/// names + MBTI strings; the app applies its own RankColors / chips).
Map<String, dynamic> _row({
  String type = 'user',
  int id = 42,
  int userId = 42,
  int postId = 0,
  String username = 'alice',
  String rank = 'SysOp',
  String personality = 'INTJ',
  String content = '',
  String postContent = '',
  String date = '',
  Map<String, dynamic> stats = const {},
}) =>
    {
      'type': type,
      'id': id,
      'user_id': userId,
      'post_id': postId,
      'username': username,
      'avatar': '/public/avatars/alice.png',
      'rank': rank,
      'personality_type': personality,
      'content': content,
      'post_content': postContent,
      'date': date,
      'stats': stats,
    };

void main() {
  test('SearchResult.fromJson maps every structured field', () {
    final r = SearchResult.fromJson(_row(
      type: 'post',
      id: 88,
      userId: 7,
      username: 'bob',
      rank: 'Admin',
      personality: 'INTP',
      content: 'A post about things',
      date: 'Aug 20, 2026',
      stats: const {'likes': 3, 'comments': 1},
    ));
    expect(r.type, 'post');
    expect(r.id, 88);
    expect(r.userId, 7);
    expect(r.username, 'bob');
    expect(r.rank, 'Admin');
    expect(r.personalityType, 'INTP');
    expect(r.content, 'A post about things');
    expect(r.stats['likes'], 3);
  });

  test('SearchResult.fromJson is defensive on missing/odd fields', () {
    final r = SearchResult.fromJson(const {
      'type': 'user',
      'username': 'carol',
      'stats': null,
    });
    expect(r.type, 'user');
    expect(r.id, 0);
    expect(r.userId, 0);
    expect(r.username, 'carol');
    expect(r.rank, 'Member', reason: 'default rank');
    expect(r.personalityType, '');
    expect(r.stats, isEmpty);
  });

  test('search() parses the real api/v1/search?format=json payload',
      () async {
    final h = await Harness.start((req) async {
      Harness.respond(
        req,
        body: jsonEncode({
          'success': true,
          'total': 3,
          'results': [
            _row(
                type: 'user',
                id: 42,
                username: 'alice',
                rank: 'SysOp',
                personality: 'INTJ',
                content: 'builder of things',
                stats: const {'posts': 12}),
            _row(
                type: 'post',
                id: 88,
                userId: 7,
                username: 'bob',
                rank: 'Admin',
                personality: 'INTP',
                content: 'A post about things',
                stats: const {'likes': 3, 'comments': 1}),
            _row(
                type: 'comment',
                id: 5,
                userId: 9,
                postId: 88,
                username: 'carol',
                rank: 'Member',
                personality: '',
                content: 'nice post',
                postContent: 'A post about things'),
          ],
        }),
        headers: const {'content-type': 'application/json'},
      );
    });
    addTearDown(h.close);

    final results = await SearchService(h.client).search('things');

    final req = h.requests.single;
    expect(req.uri.path, '/api/v1/search');
    expect(req.uri.queryParameters['q'], 'things');
    expect(req.uri.queryParameters['format'], 'json');
    expect(results, hasLength(3));
    expect(results[0].type, 'user');
    expect(results[0].rank, 'SysOp');
    expect(results[0].personalityType, 'INTJ');
    expect(results[1].type, 'post');
    expect(results[1].stats['likes'], 3);
    expect(results[2].type, 'comment');
    expect(results[2].postId, 88);
    expect(results[2].postContent, 'A post about things');
  });

  test('search() returns [] on no matches', () async {
    final h = await Harness.start((req) async {
      Harness.respond(
        req,
        body: jsonEncode(<String, dynamic>{
          'success': true,
          'total': 0,
          'results': <dynamic>[],
        }),
        headers: const {'content-type': 'application/json'},
      );
    });
    addTearDown(h.close);

    final results = await SearchService(h.client).search('zzzz');
    expect(results, isEmpty);
  });
}
