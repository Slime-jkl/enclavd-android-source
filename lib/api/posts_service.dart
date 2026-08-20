import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// PostsService — create / update / delete posts over api/v1.
///
/// Contracts (posts.php POST, all CSRF-gated via the X-CSRF-Token header):
///   create (default action, urlencoded form — same fields as the site's
///     post_form.php): content, image_data (base64 data URL, ≤10MB) +
///     is_base64_image=1 → {success, post:{id, html}}. The image travels as
///     base64 exactly like the site's ied editor output (post_max_size 32M
///     comfortably fits the encoded body).
///   update (JSON): {action:'update', post_id, content, original_content}
///     → {success, message, content}. Content ONLY — the API does not
///     replace a post's image on edit (the gallery row is untouched).
///   delete (JSON): {action:'delete', post_id, hashtags:[...]}
///     → {success}. Ownership enforced server-side (owner or admin>10 —
///     this app only ever offers the menu on own posts).
class PostsService {
  PostsService(this._api);

  final ApiClient _api;

  /// Creates a post. `content` may be empty when an image is attached
  /// (the server requires at least one). Returns the new post id.
  ///
  /// The image is compressed by image_picker at pick time (maxWidth 1600,
  /// quality 80 — the site's ied-equivalent), so uploads stay far under the
  /// 10MB base64 cap. Animated GIFs get flattened to a still JPEG frame by
  /// the picker — same tradeoff the site's editor makes.
  Future<int> createPost({required String content, XFile? image}) async {
    final fields = <String, String>{
      'content': content,
      'is_base64_image': image != null ? '1' : '0',
    };
    if (image != null) {
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const ApiException('Image too large (max 10MB).');
      }
      fields['image_data'] =
          'data:${_mimeFor(image.name)};base64,${base64Encode(bytes)}';
    }

    final token = await _api.fetchCsrfToken();
    final resp = await _api.postForm(
      '/api/v1/posts',
      fields,
      headers: {
        if (token != null && token.isNotEmpty) AppConfig.hdrCsrf: token,
      },
    );
    final json = _decode(resp, 'Failed to create post');
    final rawPost = json['post'];
    if (rawPost is! Map<String, dynamic>) {
      throw const ApiException('Invalid create response');
    }
    return (rawPost['id'] as num?)?.toInt() ?? 0;
  }

  /// Updates a post's content (images are not replaceable via the API).
  /// Returns the server's confirmation message.
  Future<String> updatePost({
    required int postId,
    required String content,
    required String originalContent,
  }) async {
    final json = await _api.postJson('/api/v1/posts', {
      'action': 'update',
      'post_id': postId,
      'content': content,
      'original_content': originalContent,
    });
    return json['message'] as String? ?? 'Post updated';
  }

  /// Deletes a post (owner only). `content` is used to extract #hashtags so
  /// the server can clean up orphan tags (delete.php contract).
  Future<void> deletePost(
      {required int postId, required String content}) async {
    await _api.postJson('/api/v1/posts', {
      'action': 'delete',
      'post_id': postId,
      'hashtags': extractHashtags(content),
    });
  }

  /// #hashtags from content, deduped (port of the server's tag cleanup input).
  static List<String> extractHashtags(String content) {
    final matches = RegExp(r'#([A-Za-z0-9_]+)').allMatches(content);
    return matches.map((m) => m.group(1)!).toSet().toList();
  }

  static String _mimeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Map<String, dynamic> _decode(RawResponse resp, String fallbackMessage) {
    if (resp.status < 200 || resp.status >= 300) {
      var message = fallbackMessage;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          message = decoded['error'] as String? ?? message;
        }
      } catch (_) {}
      throw ApiException(message, status: resp.status);
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ApiException('Invalid response from server');
  }
}
