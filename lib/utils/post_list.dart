import '../api/feed_service.dart';

/// Swap a card's updated copy back into the list that holds it, in place.
///
/// The list owns the post; a card only borrows it. Without this the list keeps
/// the load-time snapshot, so a card whose State is thrown away (scrolled past
/// the cache extent) is rebuilt from the old copy and the like disappears.
void replacePost(List<Post> posts, Post post) {
  final i = posts.indexWhere((p) => p.id == post.id);
  if (i != -1) posts[i] = post;
}
