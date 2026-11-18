import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/models/work.dart';

/// 分页作品列表控制器。
///
/// 通过构造函数注入取数逻辑，因此同一套翻页 / 加载态 / 错误态逻辑
/// 可以同时服务于首页各个栏目、浏览页与搜索结果页。
class WorkFeed extends ChangeNotifier {
  WorkFeed(this._fetch, {this.pageSize = 24, this.label = ''});

  final Future<WorksPage> Function(int page, int pageSize) _fetch;
  final int pageSize;

  /// 用于日志 / 调试的标识。
  final String label;

  final List<Work> _items = [];
  int _page = 0;
  int _totalCount = 0;
  bool _hasMore = false;
  int _generation = 0;
  bool _loadingFirstPage = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;

  List<Work> get items => List.unmodifiable(_items);
  int get page => _page;
  int get totalCount => _totalCount;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;
  bool get isEmpty => _loadedOnce && _items.isEmpty;
  bool get hasMore => _hasMore;

  bool _disposed = false;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _appendPage(WorksPage result, int page) {
    final seen = _items.map((work) => work.id).toSet();
    _items.addAll(result.works.where((work) => seen.add(work.id)));
    _page = page;
    if (page == 1 || result.totalCount > 0) _totalCount = result.totalCount;
    _hasMore = result.works.isNotEmpty && page < result.maxPage;
    _error = null;
  }

  /// 首屏加载（或筛选条件变化后重新加载）。
  Future<void> load({bool showLoading = true}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _loadingFirstPage = true;
    _loadingMore = false;
    if (showLoading) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final res = await _fetch(1, pageSize);
      if (!_isCurrent(generation)) return;
      _items.clear();
      _appendPage(res, 1);
    } catch (e) {
      if (_isCurrent(generation)) _error = e is ApiException ? e.message : '$e';
    } finally {
      if (_isCurrent(generation)) {
        _loadedOnce = true;
        _loadingFirstPage = false;
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => load(showLoading: false);

  Future<void> loadMore() async {
    if (_disposed || _loadingFirstPage || _loadingMore || !hasMore) return;
    final generation = _generation;
    _loadingMore = true;
    notifyListeners();
    try {
      final next = _page + 1;
      final res = await _fetch(next, pageSize);
      if (_isCurrent(generation)) _appendPage(res, next);
    } catch (e) {
      if (_isCurrent(generation)) _error = e is ApiException ? e.message : '$e';
    } finally {
      if (_isCurrent(generation)) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 浏览页控制器：持有查询条件并驱动 [WorkFeed]。
class BrowseController extends ChangeNotifier {
  BrowseController({WorkQuery? initial, ApiClient? api})
    : _query = initial ?? const WorkQuery(),
      _api = api ?? ApiClient.instance {
    _rebuildFeed();
  }

  WorkQuery _query;
  bool _showNsfw = true;
  late WorkFeed feed;

  WorkQuery get query => _query;
  WorkFeed get works => feed;

  final ApiClient _api;

  void _rebuildFeed() {
    final query = _query;
    feed = WorkFeed(
      (page, pageSize) =>
          _api.fetchWorks(query.copyWith(page: page, pageSize: pageSize)),
      pageSize: 24,
      label: 'browse',
    );
  }

  Future<void> update(WorkQuery next, {bool reload = true}) async {
    if (!_showNsfw) next = next.copyWith(nsfw: false);
    final queryChanged =
        next.order != _query.order ||
        next.sort != _query.sort ||
        next.tags.join(',') != _query.tags.join(',') ||
        next.circles.join(',') != _query.circles.join(',') ||
        next.vas.join(',') != _query.vas.join(',') ||
        next.rate != _query.rate ||
        next.duration != _query.duration ||
        next.subtitle != _query.subtitle ||
        next.includeTranslationWorks != _query.includeTranslationWorks ||
        next.nsfw != _query.nsfw;

    _query = next.copyWith(page: 1);
    if (queryChanged) {
      feed.dispose();
      _rebuildFeed();
    }
    notifyListeners();
    if (reload) await feed.load();
  }

  /// 只切换排序，保留其余筛选条件。
  Future<void> setOrder(WorkOrder order, SortDirection sort) =>
      update(_query.copyWith(order: order, sort: sort));

  Future<void> clearFilters() => update(const WorkQuery());

  Future<void> setShowNsfw(bool value) {
    _showNsfw = value;
    return update(
      _query.copyWith(nsfw: value ? null : false, clearNsfw: value),
    );
  }

  @override
  void dispose() {
    feed.dispose();
    super.dispose();
  }
}
