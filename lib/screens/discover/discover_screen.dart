import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/discover/hashtag_videos_screen.dart';
import 'package:vibeshort/screens/profile/public_profile_screen.dart';
import 'package:vibeshort/widgets/video_grid.dart';

/// Discover tab: search users & videos, plus trending hashtags.
///
/// Firestore cannot do substring search, so matching runs
/// client-side over bounded lists (recent videos, all profiles).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search users, videos, #hashtags',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.muted),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            color: AppTheme.muted, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _query.isEmpty ? _trending() : _results(_query),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Empty query: trending hashtags aggregated from captions
  // ---------------------------------------------------------------

  Widget _trending() {
    return StreamBuilder<List<VibeVideo>>(
      stream: FirestoreService.instance.videoFeed(limit: 200),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent));
        }
        final videos = snap.data ?? const <VibeVideo>[];
        final counts = <String, int>{};
        for (final v in videos) {
          for (final tag in v.effectiveHashtags) {
            counts[tag] = (counts[tag] ?? 0) + 1;
          }
        }
        final tags = counts.entries.toList()
          ..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            return byCount != 0 ? byCount : a.key.compareTo(b.key);
          });
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Trending hashtags',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
            ),
            if (tags.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'No hashtags yet.\nAdd #tags to your video captions and they will trend here.',
                  style: TextStyle(color: AppTheme.muted, height: 1.5),
                ),
              )
            else
              ...tags.map((e) => _hashtagRow(e.key, e.value)),
          ],
        );
      },
    );
  }

  Widget _hashtagRow(String tag, int count) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('#',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      title: Text('#$tag',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
      subtitle: Text('$count video${count == 1 ? '' : 's'}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
      trailing:
          const Icon(Icons.chevron_right, color: AppTheme.muted, size: 20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HashtagVideosScreen(tag: tag)),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Search results: Users + Videos sections
  // ---------------------------------------------------------------

  Widget _results(String query) {
    final q = query.toLowerCase().replaceFirst('#', '');
    final fs = FirestoreService.instance;
    return StreamBuilder<List<VibeUser>>(
      stream: fs.allUsers(),
      builder: (context, usnap) {
        return StreamBuilder<List<VibeVideo>>(
          stream: fs.videoFeed(limit: 200),
          builder: (context, vsnap) {
            if (usnap.connectionState == ConnectionState.waiting ||
                vsnap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent));
            }
            final users = (usnap.data ?? const <VibeUser>[])
                .where((u) =>
                    u.displayName.toLowerCase().contains(q) ||
                    u.username.toLowerCase().contains(q))
                .toList();
            final videos = (vsnap.data ?? const <VibeVideo>[])
                .where((v) =>
                    v.caption.toLowerCase().contains(q) ||
                    v.effectiveHashtags.contains(q))
                .toList();
            if (users.isEmpty && videos.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No results for "$query"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
              );
            }
            return ListView(
              children: [
                if (users.isNotEmpty) ...[
                  const _SectionHeader('Users'),
                  ...users.map(_userRow),
                ],
                if (videos.isNotEmpty) ...[
                  const _SectionHeader('Videos'),
                  VideoGrid(videos: videos),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _userRow(VibeUser u) {
    final name = u.displayOrFallback;
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppTheme.accent2,
        backgroundImage:
            u.photoUrl.isNotEmpty ? NetworkImage(u.photoUrl) : null,
        child: u.photoUrl.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))
            : null,
      ),
      title: Text(name,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
      subtitle: u.username.isNotEmpty
          ? Text('@${u.username}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12.5))
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: u.uid)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}
