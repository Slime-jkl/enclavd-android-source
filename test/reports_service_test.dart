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
