import 'package:flutter/foundation.dart';
import 'package:reader/models/blocked_content.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/uri_keys.dart';

class BlockedContentStore {
  BlockedContentStore({LocalLibraryStore? libraryStore})
    : _libraryStore = libraryStore ?? LocalLibraryStore.instance;

  static final BlockedContentStore instance = BlockedContentStore();

  final LocalLibraryStore _libraryStore;

  Future<void> ensureInitialized() => _libraryStore.ensureInitialized();

  ValueListenable<int> get revision => _libraryStore.blockedRevisionNotifier;

  List<BlockedContentItem> get items => _libraryStore.blockedItems;

  List<BlockedContentItem> itemsOfType(BlockedContentType type) {
    return items
        .where((BlockedContentItem item) => item.type == type)
        .toList(growable: false);
  }

  Future<void> blockComic({required String href, required String title}) async {
    final String key = UriKeys.rawPathKey(href);
    if (key.isEmpty) {
      return;
    }
    await _libraryStore.upsertBlocked(
      BlockedContentItem(
        type: BlockedContentType.comic,
        key: key,
        label: title.trim(),
        href: href.trim(),
      ),
    );
  }

  Future<void> blockAuthor({required String label, String href = ''}) async {
    final String normalizedHref = UriKeys.rawPathKey(href);
    final String key = normalizedHref.isNotEmpty
        ? normalizedHref
        : normalizeLabel(label);
    if (key.isEmpty) {
      return;
    }
    await _libraryStore.upsertBlocked(
      BlockedContentItem(
        type: BlockedContentType.author,
        key: key,
        label: label.trim(),
        href: href.trim(),
      ),
    );
  }

  Future<void> unblock(BlockedContentItem item) {
    return _libraryStore.removeBlocked(item.type, item.key);
  }

  bool isBlocked(BlockedContentType type, String key) {
    return _libraryStore.isBlocked(type, key);
  }

  static String normalizeLabel(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}
