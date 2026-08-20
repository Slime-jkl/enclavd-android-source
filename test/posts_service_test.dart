import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/posts_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('PostsService.createPost', () {
    test('sends urlencoded form + base64 image + CSRF header', () async {
      String? body;
      String? contentType;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="tok-post">');
        } else if (req.uri.path == '/api/v1/posts') {
          contentType = req.headers.contentType?.mimeType;
          csrf = req.headers.value('x-csrf-token');
          body = await utf8.decoder.bind(req).join();
          Harness.respond(req,
              body: '{"success":true,"post":{"id":99,"html":"<div/>"}}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final image =
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'pic.jpg');
      final id = await PostsService(h.client)
          .createPost(content: 'hello #tag', image: image);

      expect(id, 99);
      expect(contentType, 'application/x-www-form-urlencoded');
      expect(csrf, 'tok-post');
      expect(body, contains('content=hello+%23tag'));
      expect(body, contains('is_base64_image=1'));
      expect(body, contains('image_data=data%3Aimage%2Fjpeg%3Bbase64%2CAQID'));

      await h.close();
    });

    test('text-only post sends is_base64_image=0 and no image_data', () async {
      String? body;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          body = await utf8.decoder.bind(req).join();
          Harness.respond(req,
              body: '{"success":true,"post":{"id":7,"html":""}}');
        }
      });

      final id = await PostsService(h.client).createPost(content: 'plain text');
      expect(id, 7);
      expect(body, contains('is_base64_image=0'));
      expect(body, isNot(contains('image_data')));

      await h.close();
    });

    test('server 400 surfaces its message', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          Harness.respond(req,
              status: 400,
              body: '{"error":"Post must contain either text or an image"}');
        }
      });

      await expectLater(
        PostsService(h.client).createPost(content: ''),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message',
                'Post must contain either text or an image')),
      );
      await h.close();
    });
  });

  group('PostsService.updatePost', () {
    test('sends JSON action update with post_id + original_content', () async {
      String? body;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="tok-upd">');
        } else if (req.uri.path == '/api/v1/posts') {
          body = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(req,
              body:
                  '{"success":true,"message":"Post updated successfully","content":"new text"}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final message = await PostsService(h.client).updatePost(
        postId: 42,
        content: 'new text',
        originalContent: 'old text',
      );
      expect(message, 'Post updated successfully');
      expect(csrf, 'tok-upd');
      final sent = jsonDecode(body!) as Map<String, dynamic>;
      expect(sent['action'], 'update');
      expect(sent['post_id'], 42);
      expect(sent['content'], 'new text');
      expect(sent['original_content'], 'old text');

      await h.close();
    });
  });

  group('PostsService.deletePost', () {
    test('sends action delete + deduped hashtags from content', () async {
      String? body;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          body = await utf8.decoder.bind(req).join();
          Harness.respond(req, body: '{"success":true}');
        }
      });

      await PostsService(h.client).deletePost(
        postId: 42,
        content: 'hello #one and #two plus #one again',
      );
      final sent = jsonDecode(body!) as Map<String, dynamic>;
      expect(sent['action'], 'delete');
      expect(sent['post_id'], 42);
      expect(sent['hashtags'], ['one', 'two']);

      await h.close();
    });
  });

  group('extractHashtags', () {
    test('dedupes and ignores invalid characters', () {
      expect(PostsService.extractHashtags('no tags here'), isEmpty);
      expect(PostsService.extractHashtags('#one #two #one'), ['one', 'two']);
      expect(PostsService.extractHashtags('x #a_b-c'), ['a_b']);
    });
  });
}
