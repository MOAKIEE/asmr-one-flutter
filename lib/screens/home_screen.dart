import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/data/featured_tags.dart';
import '../core/models/common.dart';
import '../core/models/work.dart';
import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../state/settings_state.dart';
import '../widgets/work_card.dart';
import '../widgets/work_rail.dart';
import 'tag_browse_screen.dart';
import 'work_list_screen.dart';

/// 首页：头部问候 + 热门标签 + 若干榜单横滑区。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 变化时重建所有横滑区，实现下拉刷新。
  int _tick = 0;
  bool _loadingRandom = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final nsfw = settings.showNsfw ? null : false;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _tick++),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _HomeHeader(
              loadingRandom: _loadingRandom,
              onRandom: _openRandom,
              onBrowseAll: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkListScreen(
                    title: l('nav.browse'),
                    query: WorkQuery(nsfw: nsfw),
                  ),
                ),
              ),
            ),
            WorkRail(
              key: ValueKey('hot-$_tick'),
              title: l('home.hot'),
              icon: Icons.local_fire_department_rounded,
              query: WorkQuery(order: WorkOrder.dlCount, nsfw: nsfw),
              onSeeAll: () => _openAll(l('home.hot'), WorkOrder.dlCount, nsfw),
            ),
            WorkRail(
              key: ValueKey('new-$_tick'),
              title: l('home.new'),
              icon: Icons.new_releases_rounded,
              query: WorkQuery(order: WorkOrder.createDate, nsfw: nsfw),
              onSeeAll: () =>
                  _openAll(l('home.new'), WorkOrder.createDate, nsfw),
            ),
            WorkRail(
              key: ValueKey('top-$_tick'),
              title: l('home.top'),
              icon: Icons.workspace_premium_rounded,
              query: WorkQuery(
                order: WorkOrder.rateAverage,
                nsfw: nsfw,
                rate: 4.5,
              ),
              onSeeAll: () =>
                  _openAll(l('home.top'), WorkOrder.rateAverage, nsfw),
            ),
            WorkRail(
              key: ValueKey('rev-$_tick'),
              title: l('home.reviewed'),
              icon: Icons.forum_rounded,
              query: WorkQuery(order: WorkOrder.reviewCount, nsfw: nsfw),
              onSeeAll: () =>
                  _openAll(l('home.reviewed'), WorkOrder.reviewCount, nsfw),
            ),
            WorkRail(
              key: ValueKey('free-$_tick'),
              title: l('work.free'),
              icon: Icons.card_giftcard_rounded,
              query: WorkQuery(order: WorkOrder.dlCount, nsfw: nsfw, rate: 4.0),
              onSeeAll: () => _openAll(l('work.free'), WorkOrder.dlCount, nsfw),
            ),
          ],
        ),
      ),
    );
  }

  void _openAll(String title, WorkOrder order, bool? nsfw) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkListScreen(
          title: title,
          query: WorkQuery(order: order, nsfw: nsfw),
        ),
      ),
    );
  }

  Future<void> _openRandom() async {
    if (_loadingRandom) return;
    setState(() => _loadingRandom = true);
    final settings = context.read<SettingsState>();
    try {
      final work = await ApiClient.instance.randomWork(
        nsfw: settings.showNsfw ? null : false,
      );
      if (!mounted) return;
      if (work == null) {
        _toast(L10n.of(context)('error.empty'));
        return;
      }
      openWork(context, work);
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => _loadingRandom = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.onRandom,
    required this.onBrowseAll,
    required this.loadingRandom,
  });

  final VoidCallback onRandom;
  final VoidCallback onBrowseAll;
  final bool loadingRandom;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;

    final hotTags = FeaturedTags.resolve();

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 22, 20, 20),
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(scheme),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: scheme.onPrimary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l('app.name'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l('app.tagline'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l('home.greeting'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onPrimary,
              fontSize: 25,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: loadingRandom ? null : onRandom,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onPrimary,
                    foregroundColor: scheme.primary,
                  ),
                  icon: loadingRandom
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.shuffle_rounded, size: 18),
                  label: Text(l('home.random')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBrowseAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onPrimary,
                    side: BorderSide(
                      color: scheme.onPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: Text(l('common.seeAll')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hotTags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final tag = hotTags[i];
                return Material(
                  color: scheme.onPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TagBrowseScreen(initialTag: tag),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        '# ${tag.label(AppLang.zh)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
