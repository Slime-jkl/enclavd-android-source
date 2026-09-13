import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// Create / update / delete posts over api/v1 (posts.php POST, all
/// CSRF-gated via the X-CSRF-Token header). create = multipart form, same
/// fields as the site's post_form.php: content plus either the single-image
/// fields (image_data base64 data URL <= 10MB, is_base64_image=1) or, for a
/// carousel, images_data (JSON array of up to 6 data URLs) with
/// is_multiple_images=1; update (JSON) is content ONLY - the API never
/// replaces a post's images on edit; delete (JSON) sends the #hashtags for
/// orphan-tag cleanup, ownership enforced server-side.
class PostsService {
  PostsService(this._api);

  final ApiClient _api;

  /// Slides one post may carry (the server enforces the same cap).
  static const int maxImages = 6;

  /// Creates a post (`content` may be empty when an image is attached;
  /// the server requires at least one). Returns the new post id.
  ///
  /// Every image arrives already baked (<=1200px, JPEG q85) by the editor
  /// or the picker, so uploads stay far under the caps. A single image
  /// keeps the original single-image fields, so one-image posts work even
  /// against a server that predates the carousel; two or more use the
  /// carousel fields, exactly as the website composer sends them.
  Future<int> createPost({
    required String content,
    List<XFile> images = const [],
  }) async {
    if (images.length > maxImages) {
      throw const ApiException('Up to $maxImages images per post.');
    }

    final fields = <String, String>{'content': content};

    if (images.isEmpty) {
      fields['is_base64_image'] = '0';
    } else if (images.length == 1) {
      final file = images.first;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const ApiException('Image too large (max 10MB).');
      }
      fields['is_base64_image'] = '1';
      fields['image_data'] =
          'data:${_mimeFor(file.name)};base64,${base64Encode(bytes)}';
    } else {
      final slides = <String>[];
      for (final file in images) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          throw const ApiException('Each image must be under 5MB.');
        }
        slides.add('data:${_mimeFor(file.name)};base64,${base64Encode(bytes)}');
      }
      // Slides for a server that knows the carousel, plus the lead image in
      // the single-image fields so a server that does not know it yet still
      // posts the first image instead of rejecting the whole thing.
      fields['is_multiple_images'] = '1';
      fields['images_data'] = jsonEncode(slides);
      fields['is_base64_image'] = '1';
      fields['image_data'] = slides.first;
    }

    final token = await _api.fetchCsrfToken();
    final resp = await _api.postFormMultipart(
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

  /// Updates a post's content (images are not replaceable via the API);
  /// returns the server's confirmation message.
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

  /// Deletes a post (owner only); content's #hashtags let the server clean
  /// up orphan tags (delete.php contract).
  Future<void> deletePost(
      {required int postId, required String content}) async {
    await _api.postJson('/api/v1/posts', {
      'action': 'delete',
      'post_id': postId,
      'hashtags': extractHashtags(content),
    });
  }

  /// #hashtags from content, deduped (port of the server's tag cleanup
  /// input).
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
    throw const ApiException('Something went wrong on our side. Please try again.');
  }
}
