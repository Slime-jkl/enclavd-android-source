import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/reports_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('ReportsService.list', () {
    test('GETs /api/v1/reports and splits open/closed like the site',
        () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/reports') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'reports': [
                {
                  'id': 2,
                  'submission_type': 'Closed',
                  'submission_content': 'fixed',
                  'submission_status': 'Closed',
                  'submission_date': '2026-08-01 10:00',
                },
                {
                  'id': 3,
                  'submission_type': 'Bug',
                  'submission_content': 'still broken',
                  'submission_status': 'Open',
                  'submission_date': '2026-08-20 09:15',
                },
              ],
              'total': 2,
              'page': 1,
              'total_pages': 1,
              'allowed_types': [
                'Bug',
                'Account issue',
                'Abuse / report user',
                'Feedback',
                'Feature request',
                'Other',
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final page = await ReportsService(h.client).list();
      expect(query, 'page=1');
      expect(page.total, 2);
      expect(page.open, hasLength(1));
      expect(page.closed, hasLength(1));
      expect(page.open.first.content, 'still broken');
      expect(page.closed.first.content, 'fixed');
      expect(page.allowedTypes, contains('Bug'));
      expect(page.allowedTypes, contains('Other'));
      await h.close();
    });
  });

  group('ReportsService.fetchDetail / reply / mark_solved', () {
    test('GET ?id=N parses ticket, owner and the merged timeline',
        () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/reports') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'ticket': {
                'id': 3,
                'submission_type': 'Bug',
                'submission_content': 'detail flow',
                'submission_status': 'Pending',
                'submission_date': '2026-08-21 20:17',
                'submission_solved_date': null,
              },
              'owner': {
                'id': 1,
                'username': 'Developer',
                'rank': 'SysOp',
                'is_active': 'true',
                'profile_picture_url': '/public/avatars/a.jpg',
              },
              'events': [
                {
                  'type': 'reply',
                  'date': '2026-08-21 20:17:46',
                  'content': 'my first reply',
                  'username': 'Developer',
                  'profile_picture_url': '/public/avatars/a.jpg',
                  'rank': 'SysOp',
                  'is_active': 'true',
                },
                {
                  'type': 'log',
                  'date': '2026-08-21 20:18:00',
                  'ticket_log': 'Developer changed the status to Closed',
                },
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final d = await ReportsService(h.client).fetchDetail(3);
      expect(query, 'id=3');
      expect(d.id, 3);
      expect(d.status, 'Pending');
      expect(d.isClosed, isFalse);
      expect(d.owner!.username, 'Developer');
      expect(d.events, hasLength(2));
      expect(d.events.first.isLog, isFalse);
      expect(d.events.first.content, 'my first reply');
      expect(d.events.last.isLog, isTrue);
      expect(d.events.last.ticketLog,
          'Developer changed the status to Closed');
      await h.close();
    });

    test('addReply POSTs action=reply with CSRF', () async {
      String? rawBody;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="tok-r">');
        } else if (req.uri.path == '/api/v1/reports') {
          rawBody = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(req, body: '{"success":true}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      await ReportsService(h.client)
          .addReply(ticketId: 3, content: 'hello');
      expect(csrf, 'tok-r');
      expect(rawBody,
          contains('"action":"reply","ticket_id":3,"reply_content":"hello"'));
      await h.close();
    });

    test('markSolved POSTs action=mark_solved', () async {
      String? rawBody;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/reports') {
          rawBody = await utf8.decoder.bind(req).join();
          Harness.respond(req, body: '{"success":true}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      await ReportsService(h.client).markSolved(3);
      expect(rawBody, '{"action":"mark_solved","ticket_id":3}');
      await h.close();
    });
  });

  group('ReportsService.create', () {
    test('POSTs action=create with type + content and CSRF', () async {
      String? rawBody;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="tok-r">');
        } else if (req.uri.path == '/api/v1/reports') {
          rawBody = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'report': {
                'id': 9,
                'submission_type': 'Bug',
                'submission_content': 'api test',
                'submission_status': 'Open',
                'submission_date': '2026-08-21 12:00',
              },
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final t = await ReportsService(h.client)
          .create(type: 'Bug', content: 'api test');
      expect(csrf, 'tok-r');
      expect(rawBody, contains('"action":"create"'));
      expect(rawBody, contains('"submission_type":"Bug"'));
      expect(rawBody, contains('"submission_content":"api test"'));
      expect(t.id, 9);
      expect(t.status, 'Open');
      expect(t.isClosed, isFalse);
      await h.close();
    });

    test('400 validation error surfaces with the site message', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          Harness.respond(req,
              status: 400,
              body:
                  '{"error":"Please describe the issue you are reporting."}');
        }
      });
      await expectLater(
        ReportsService(h.client)
            .create(type: 'Bug', content: ''),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', contains('Please describe'))),
      );
      await h.close();
    });
  });
}
