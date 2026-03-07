import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:flutter/material.dart';

class ProfilePageView extends StatelessWidget {
  const ProfilePageView({
    required this.page,
    required this.onAuthenticate,
    required this.onLogout,
    required this.onOpenComic,
    required this.onOpenHistory,
    this.afterContinueReading,
    super.key,
  });

  final ProfilePageData page;
  final VoidCallback onAuthenticate;
  final VoidCallback onLogout;
  final ValueChanged<String> onOpenComic;
  final ValueChanged<ProfileHistoryItem> onOpenHistory;
  final Widget? afterContinueReading;

  @override
  Widget build(BuildContext context) {
    if (!page.isLoggedIn || page.user == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.person_outline_rounded, size: 48),
            const SizedBox(height: 14),
            Text(
              page.message.isEmpty ? '登录后可查看收藏与历史。' : page.message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAuthenticate,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('登录 / 注册'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final ProfileUserData user = page.user!;
    return Column(
      children: <Widget>[
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _AvatarImage(imageUrl: user.avatarUrl),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          user.username,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (user.createdAt.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '注册于 ${user.createdAt}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
              if (user.membershipLabel.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    user.membershipLabel,
                    style: const TextStyle(
                      color: Color(0xFF2D6CF4),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (page.continueReading != null) ...<Widget>[
          const SizedBox(height: 18),
          _SectionCard(
            title: '继续阅读',
            child: _HistoryTile(
              item: page.continueReading!,
              onTap: () => onOpenHistory(page.continueReading!),
            ),
          ),
        ],
        if (afterContinueReading != null) ...<Widget>[
          const SizedBox(height: 18),
          afterContinueReading!,
        ],
        if (page.collections.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _SectionCard(
            title: '我的收藏',
            child: SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: page.collections.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) {
                  final ProfileLibraryItem item = page.collections[index];
                  return SizedBox(
                    width: 136,
                    child: _LibraryCard(
                      item: item,
                      onTap: () => onOpenComic(item.href),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (page.history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _SectionCard(
            title: '浏览历史',
            child: Column(
              children: page.history
                  .map(
                    (ProfileHistoryItem item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryTile(
                        item: item,
                        onTap: () => onOpenHistory(item),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const CircleAvatar(radius: 28, child: Icon(Icons.person_rounded));
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        cacheManager: EasyCopyImageCaches.coverCache,
        errorWidget: (_, __, ___) {
          return const CircleAvatar(
            radius: 28,
            child: Icon(Icons.person_rounded),
          );
        },
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.item, required this.onTap});

  final ProfileLibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: item.coverUrl.isEmpty
                  ? const _PlaceholderBox()
                  : CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheManager: EasyCopyImageCaches.coverCache,
                      errorWidget: (_, __, ___) => const _PlaceholderBox(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (item.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onTap});

  final ProfileHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 68,
              height: 92,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: item.coverUrl.isEmpty
                    ? const _PlaceholderBox()
                    : CachedNetworkImage(
                        imageUrl: item.coverUrl,
                        fit: BoxFit.cover,
                        cacheManager: EasyCopyImageCaches.coverCache,
                        errorWidget: (_, __, ___) => const _PlaceholderBox(),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.chapterLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (item.visitedAt.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      item.visitedAt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFE4E7ED), Color(0xFFD3D9E4)],
        ),
      ),
      child: Center(
        child: Icon(Icons.image_outlined, color: Color(0xFF5B6577)),
      ),
    );
  }
}
