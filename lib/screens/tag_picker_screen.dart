import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/common.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';

/// 多选标签页。返回值：
/// * `List<int>` —— 用户点「确定」后的选择
/// * `null` —— 用户直接返回（不修改）
class TagPickerScreen extends StatefulWidget {
  const TagPickerScreen({super.key, this.initial = const []});

  final List<int> initial;

  @override
  State<TagPickerScreen> createState() => _TagPickerScreenState();
}

class _TagPickerScreenState extends State<TagPickerScreen> {
  late final Set<int> _selected = widget.initial.toSet();
  final _controller = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final lang = _appLang(context);
    final auth = context.watch<AuthState>();
    final all = auth.tags;
    final list = _keyword.isEmpty
        ? all
        : all
              .where(
                (t) =>
                    t
                        .label(AppLang.zh)
                        .toLowerCase()
                        .contains(_keyword.toLowerCase()) ||
                    t
                        .label(AppLang.ja)
                        .toLowerCase()
                        .contains(_keyword.toLowerCase()) ||
                    t
                        .label(AppLang.en)
                        .toLowerCase()
                        .contains(_keyword.toLowerCase()),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l('work.tags')),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: Text(l('common.reset')),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pop(_selected.toList()),
        icon: const Icon(Icons.check_rounded),
        label: Text('${l('common.confirm')} (${_selected.length})'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _keyword = v),
              decoration: InputDecoration(
                hintText: l('tag.searchHint'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _keyword = '');
                        },
                      ),
              ),
            ),
          ),
          if (auth.usingBundledTags)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l('tag.bundledHint'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? EmptyView(message: l('common.empty'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final tag = list[i];
                      final selected = _selected.contains(tag.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TagRow(
                          label: tag.label(lang),
                          secondary: _secondaryLabel(tag, lang),
                          count: tag.count,
                          selected: selected,
                          onTap: () => setState(() {
                            if (selected) {
                              _selected.remove(tag.id);
                            } else {
                              _selected.add(tag.id);
                            }
                          }),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _secondaryLabel(Tag tag, AppLang lang) {
    if (lang == AppLang.zh) return tag.label(AppLang.ja);
    if (lang == AppLang.ja) return tag.label(AppLang.en);
    return tag.label(AppLang.zh);
  }

  AppLang _appLang(BuildContext context) {
    final locale = Localizations.localeOf(context);
    switch (locale.languageCode) {
      case 'ja':
        return AppLang.ja;
      case 'en':
        return AppLang.en;
      default:
        return AppLang.zh;
    }
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.label,
    required this.secondary,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String secondary;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : scheme.surfaceContainerHigh.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (secondary.isNotEmpty && secondary != label)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          secondary,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 21,
                color: selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
