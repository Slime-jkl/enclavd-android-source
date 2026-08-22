import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/site_config_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('SiteConfigService.fetch', () {
    test('parses the full site config', () async {
      final h = await Harness.start((req) async {
        expect(req.uri.path, '/api/v1/site_config');
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'config': {
              'isInvitationRequired': true,
              'maintenance': {
                'enabled': true,
                'allowed_ranks': ['SysOp', 'Admin', 'Moderator'],
                'reason': 'Standard Maintenance.',
                'estTime': 'Tomorrow 10:00',
              },
              'rate_limit': {
                'enabled': true,
                'cooldowns': {'1': 5, '2': 10, '3': 30},
                'captcha_at': 3,
                'lock_at': 10,
                'lock_duration': 900,
                'applies_to': ['login', 'register'],
              },
            },
          }),
        );
      });

      final service = SiteConfigService(h.client);
      final cfg = await service.fetch();

      expect(cfg.isInvitationRequired, isTrue);
      expect(cfg.maintenance.enabled, isTrue);
      expect(cfg.maintenance.allowedRanks, ['SysOp', 'Admin', 'Moderator']);
      expect(cfg.maintenance.reason, 'Standard Maintenance.');
      expect(cfg.maintenance.estTime, 'Tomorrow 10:00');
      expect(cfg.rateLimit.enabled, isTrue);
      expect(cfg.rateLimit.cooldowns, {1: 5, 2: 10, 3: 30});
      expect(cfg.rateLimit.captchaAt, 3);
      expect(cfg.rateLimit.lockAt, 10);
      expect(cfg.rateLimit.appliesTo, ['login', 'register']);

      await h.close();
    });

    test('defaults when the payload is sparse (old/partial deploy)', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
            req, body: '{"success":true,"config":{"isInvitationRequired":false}}');
      });

      final cfg = await SiteConfigService(h.client).fetch();
      expect(cfg.isInvitationRequired, isFalse);
      expect(cfg.maintenance.enabled, isFalse);
      expect(cfg.maintenance.allowedRanks, isEmpty);
      expect(cfg.rateLimit.enabled, isTrue);
      expect(cfg.rateLimit.cooldowns, isEmpty);

      await h.close();
    });
  });

  group('SiteConfigService.rateState', () {
    test('sends action/context and parses the state + captcha question',
        () async {
      final h = await Harness.start((req) async {
        expect(req.uri.path, '/api/v1/auth');
        expect(req.uri.queryParameters['action'], 'rate_state');
        expect(req.uri.queryParameters['context'], 'login');
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'state': {
              'blocked': false,
              'cooldown': 30,
              'needs_captcha': true,
              'captcha_ok': false,
              'lock_remaining': 0,
              'captcha': {'question': 'How many sides does a triangle have?'},
            },
          }),
        );
      });

      final state = await SiteConfigService(h.client).rateState('login');

      expect(state.blocked, isFalse);
      expect(state.cooldown, 30);
      expect(state.needsCaptcha, isTrue);
      expect(state.captchaOk, isFalse);
      expect(state.captchaQuestion, 'How many sides does a triangle have?');
      expect(state.captchaRequired, isTrue);
      expect(state.waitSeconds, 30);

      await h.close();
    });

    test('captcha null when not assigned; captchaRequired false when solved',
        () async {
      final h = await Harness.start((req) async {
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'state': {
              'blocked': true,
              'cooldown': 0,
              'needs_captcha': true,
              'captcha_ok': true,
              'lock_remaining': 900,
              'captcha': null,
            },
          }),
        );
      });

      final state = await SiteConfigService(h.client).rateState('login');
      expect(state.blocked, isTrue);
      expect(state.lockRemaining, 900);
      expect(state.captchaQuestion, isNull);
      expect(state.captchaRequired, isFalse,
          reason: 'already solved in this window');
      expect(state.waitSeconds, 900, reason: 'lock wins over cooldown');

      await h.close();
    });
  });
}
