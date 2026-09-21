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
  bool get hasMore => _items.length < _totalCount;

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// 首屏加载（或筛选条件变化后重新加载）。
  Future<void> load({bool showLoading = true}) async {
    if (_disposed) return;
    if (showLoading) {
      _loading = true;
      _error = null;
      _safeNotify();
    }
    try {
      final res = await _fetch(1, pageSize);
      _items
        ..clear()
        ..addAll(res.works);
      _page = 1;
      _totalCount = res.totalCount;
      _error = null;
      _loadedOnce = true;
    } on ApiException catch (e) {
      _error = e.message;
      _loadedOnce = true;
    } catch (e) {
      _error = '$e';
      _loadedOnce = true;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  Future<void> refresh() => load(showLoading: false);

  Future<void> loadMore() async {
    if (_disposed || _loading || _loadingMore || !hasMore) return;
    _loadingMore = true;
    _safeNotify();
    try {
      final next = _page + 1;
      final res = await _fetch(next, pageSize);
      // 去重，避免服务端在随机排序下重复返回同一作品。
      final seen = _items.map((e) => e.id).toSet();
      _items.addAll(res.works.where((w) => seen.add(w.id)));
      _page = next;
      if (res.totalCount > 0) _totalCount = res.totalCount;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 浏览页控制器：持有查询条件并驱动 [WorkFeed]。
class BrowseController extends ChangeNotifier {
  BrowseController({WorkQuery? initial})
    : _query = initial ?? const WorkQuery() {
    _rebuildFeed();
  }

  WorkQuery _query;
  late WorkFeed feed;

  WorkQuery get query => _query;
  WorkFeed get works => feed;

  final ApiClient _api = ApiClient.instance;

  void _rebuildFeed() {
    feed = WorkFeed(
      (page, pageSize) =>
          _api.fetchWorks(_query.copyWith(page: page, pageSize: pageSize)),
      pageSize: 24,
      label: 'browse',
    );
  }

  Future<void> update(WorkQuery next, {bool reload = true}) async {
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

  @override
  void dispose() {
    feed.dispose();
    super.dispose();
  }
}
