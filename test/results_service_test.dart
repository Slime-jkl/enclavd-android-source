import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/results_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('ResultsService.fetchResults', () {
    test('GETs /api/v1/results and parses traits + personality info',
        () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/results') {
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'results': {
                'personality_type': 'INTJ',
                'color': 'gold',
                'expires_on': '2035-12-01 00:00:00',
                'traits': {
                  'ie_percentage': 88,
                  'sn_percentage': 18,
                  'tf_percentage': 100,
                  'jp_percentage': 64,
                },
                'info': {
                  'title': 'Strategic, Visionary',
                  'description': 'INTJs are known for their brilliant minds.',
                  'strengths': [
                    'Highly analytical',
                    'Innovative',
                    'Sees the big picture',
                  ],
                  'weaknesses': [
                    'Can struggle with interpersonal relationships',
                  ],
                },
              },
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final r = await ResultsService(h.client).fetchResults();
      expect(r.personalityType, 'INTJ');
      expect(r.color, 'gold');
      expect(r.expiresOn, '2035-12-01 00:00:00');
      expect(r.iePercentage, 88);
      expect(r.snPercentage, 18);
      expect(r.tfPercentage, 100);
      expect(r.jpPercentage, 64);
      expect(r.title, 'Strategic, Visionary');
      expect(r.strengths, ['Highly analytical', 'Innovative', 'Sees the big picture']);
      expect(r.weaknesses, ['Can struggle with interpersonal relationships']);
      await h.close();
    });

    test('404 (no valid test) surfaces as ApiException status 404',
        () async {
      final h = await Harness.start((req) async {
        Harness.respond(req,
            status: 404, body: '{"error":"No test results yet"}');
      });
      await expectLater(
        ResultsService(h.client).fetchResults(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'No test results yet')),
      );
      await h.close();
    });
  });
}
