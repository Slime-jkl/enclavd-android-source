import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/invitations_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('InvitationsService.list', () {
    test('GETs /api/v1/invitations and parses count + invites', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/invitations') {
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'invite_count': 3,
              'invitations': [
                {
                  'id': 66,
                  'code': 'da67968aa90accc28f0f73c1e16d0c',
                  'status': 'pending',
                  'valid_until': '2026-09-20 22:37:04',
                },
                {
                  'id': 65,
                  'code': 'aaa',
                  'status': 'accepted',
                  'valid_until': '2026-08-01 10:00:00',
                },
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final list = await InvitationsService(h.client).list();
      expect(list.inviteCount, 3);
      expect(list.items, hasLength(2));
      expect(list.items.first.code, 'da67968aa90accc28f0f73c1e16d0c');
      expect(list.items.first.status, 'pending');
      expect(list.items.first.deletable, isTrue);
      expect(list.items.last.status, 'accepted');
      expect(list.items.last.deletable, isFalse,
          reason: 'accepted invites cannot be deleted (site parity)');
      await h.close();
    });
  });

  group('InvitationsService.create/delete', () {
    test('create POSTs action=create with CSRF, parses new invite',
        () async {
      String? rawBody;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="tok-i">');
        } else if (req.uri.path == '/api/v1/invitations') {
          rawBody = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'invite_count': 1,
              'invitation': {
                'id': 68,
                'code': 'abc123',
                'status': 'pending',
                'valid_until': '2026-09-20 22:37:04',
              },
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final created = await InvitationsService(h.client).create();
      expect(rawBody, '{"action":"create"}');
      expect(csrf, 'tok-i');
      expect(created.inviteCount, 1);
      expect(created.item.id, 68);
      expect(created.item.code, 'abc123');
      await h.close();
    });

    test('delete POSTs the id and returns the fresh count', () async {
      String? rawBody;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/invitations') {
          rawBody = await utf8.decoder.bind(req).join();
          Harness.respond(req,
              body: '{"success":true,"invite_count":2}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final count = await InvitationsService(h.client).delete(68);
      expect(rawBody, '{"action":"delete","invitation_id":68}');
      expect(count, 2);
      await h.close();
    });

    test('403 (not yours / accepted) surfaces as ApiException', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          Harness.respond(req,
              status: 403,
              body: '{"error":"You don\'t have permission to delete this '
                  'invitation"}');
        }
      });
      await expectLater(
        InvitationsService(h.client).delete(65),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 403)),
      );
      await h.close();
    });
  });

  group('formatInviteExpiry (site date(M j, Y H:i) port)', () {
    test('DB UTC wall-clock → local, 24h time', () {
      // Noon UTC stays on the same day in every timezone; the exact hour
      // depends on the test runner's zone.
      final t = formatInviteExpiry('2026-09-20 12:00:00');
      expect(t, startsWith('Sep 20, 2026 '));
      expect(t, endsWith(':00'));
      expect(formatInviteExpiry('garbage'), '');
    });
  });
}
