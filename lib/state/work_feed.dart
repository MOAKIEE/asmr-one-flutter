import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/models/work.dart';

/// 分页作品列表控制器。
///
/// 通过构造函数注入取数逻辑，因此同一套翻页 / 加载态 / 错误态逻辑
/// 可以同时服务于首页各个栏目、浏览页与搜索结果页。
class WorkFeed extends ChangeNotifier {
  WorkFeed(
    this._fetch, {
    this.pageSize = 24,
    this.label = '',
    this.filter,
    this.maxAutoAdvancePages = 5,
  });

  final Future<WorksPage> Function(int page, int pageSize) _fetch;
  final int pageSize;

  /// 用于日志 / 调试的标识。
  final String label;

  /// 可选的本地过滤函数（例如在服务端不支持分级参数时按全年龄过滤）。
  /// 翻页终止条件仍以服务端原始页为准，不会把全页过滤后的空列表误判为终页。
  final bool Function(Work work)? filter;

  /// 当启用本地过滤且整页被过滤为空时，单次加载最多自动继续向后翻的页数。
  final int maxAutoAdvancePages;

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
  bool _errorIsAuth = false;

  List<Work> get items => List.unmodifiable(_items);
  int get page => _page;
  int get totalCount => _totalCount;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;
  bool get errorIsAuth => _errorIsAuth;
  bool get isEmpty => _loadedOnce && _items.isEmpty && !_hasMore;
  bool get hasMore => _hasMore;

  bool _disposed = false;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  int _appendPage(WorksPage result, int page) {
    final seen = _items.map((work) => work.id).toSet();
    final raw = result.works;
    final visible = filter == null ? raw : raw.where(filter!);
    var added = 0;
    for (final work in visible) {
      if (seen.add(work.id)) {
        _items.add(work);
        added++;
      }
    }
    _page = page;
    if (page == 1 || result.totalCount > 0) _totalCount = result.totalCount;
    _hasMore = raw.isNotEmpty && page < result.maxPage;
    _error = null;
    _errorIsAuth = false;
    return added;
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
      _errorIsAuth = false;
      notifyListeners();
    }
    try {
      final res = await _fetch(1, pageSize);
      if (!_isCurrent(generation)) return;
      _items.clear();
      _appendPage(res, 1);
      var advanced = 0;
      while (filter != null &&
          _items.isEmpty &&
          _hasMore &&
          advanced < maxAutoAdvancePages) {
        advanced++;
        final next = _page + 1;
        final nextRes = await _fetch(next, pageSize);
        if (!_isCurrent(generation)) return;
        _appendPage(nextRes, next);
      }
    } catch (e) {
      if (_isCurrent(generation)) {
        _error = e is ApiException ? e.message : '$e';
        _errorIsAuth = e is ApiException && e.isAuthError;
      }
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
      if (!_isCurrent(generation)) return;
      var added = _appendPage(res, next);
      var advanced = 0;
      while (filter != null &&
          added == 0 &&
          _hasMore &&
          advanced < maxAutoAdvancePages) {
        advanced++;
        final morePage = _page + 1;
        final moreRes = await _fetch(morePage, pageSize);
        if (!_isCurrent(generation)) return;
        added += _appendPage(moreRes, morePage);
      }
    } catch (e) {
      if (_isCurrent(generation)) {
        _error = e is ApiException ? e.message : '$e';
        _errorIsAuth = e is ApiException && e.isAuthError;
      }
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
    _errorIsAuth = false;
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
