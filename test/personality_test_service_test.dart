import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/personality_test_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('PersonalityTestService.fetchTest', () {
    test('GETs the endpoint and parses questions + already_taken',
        () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/personality_test') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'already_taken': false,
              'questions': [
                {'id': 1, 'question': 'I prefer quiet environments.'},
                {'id': 2, 'question': 'I get energy from gatherings.'},
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final info =
          await PersonalityTestService(h.client).fetchTest();
      expect(query, isEmpty);
      expect(info.alreadyTaken, false);
      expect(info.questions, hasLength(2));
      expect(info.questions.first.id, 1);
      expect(info.questions.first.question, 'I prefer quiet environments.');
      expect(info.questions.last.id, 2);

      await h.close();
    });

    test('already_taken=true parses', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/personality_test') {
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'already_taken': true,
              'questions': <Object>[],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final info = await PersonalityTestService(h.client).fetchTest();
      expect(info.alreadyTaken, true);
      expect(info.questions, isEmpty);

      await h.close();
    });
  });

  group('PersonalityTestService.submit', () {
    test('POSTs JSON + CSRF answers and parses the result', () async {
      String? rawBody;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="tok-test">');
        } else if (req.uri.path == '/api/v1/personality_test') {
          rawBody = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'personality_type': 'ISTJ',
              'color': 'orange',
              'expires_on': '2036-08-22 00:11:23',
              'traits': {
                'ie_percentage': 100,
                'sn_percentage': 100,
                'tf_percentage': 100,
                'jp_percentage': 100,
              },
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final r = await PersonalityTestService(h.client).submit({
        1: 'strongly_agree',
        2: 'disagree',
      });
      expect(csrf, 'tok-test');
      expect(rawBody, contains('"question_1":"strongly_agree"'));
      expect(rawBody, contains('"question_2":"disagree"'));
      expect(r.personalityType, 'ISTJ');
      expect(r.color, 'orange');
      expect(r.iePercentage, 100);
      expect(r.snPercentage, 100);
      expect(r.tfPercentage, 100);
      expect(r.jpPercentage, 100);

      await h.close();
    });

    test('409 surfaces as ApiException (test already completed)',
        () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          Harness.respond(
              req,
              status: 409,
              body: '{"error":"Test already completed"}');
        }
      });

      await expectLater(
        PersonalityTestService(h.client)
            .submit(const {1: 'neutral'}),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.message, 'message',
                contains('already completed'))),
      );
      await h.close();
    });
  });
}
