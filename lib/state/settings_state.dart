import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/storage/app_prefs.dart';
import '../core/theme/app_theme.dart';

/// 全局设置状态：主题、语言、内容偏好、网络线路、播放偏好。
class SettingsState extends ChangeNotifier {
  SettingsState(this._prefs) {
    _api.attachPrefs(_prefs);
  }

  final AppPrefs _prefs;
  final ApiClient _api = ApiClient.instance;

  AppPrefs get prefs => _prefs;

  // --- 主题 ---
  ThemeMode get themeMode => _prefs.themeMode;

  set themeMode(ThemeMode v) {
    if (v == themeMode) return;
    _prefs.themeMode = v;
    notifyListeners();
  }

  int get accentSeed => _prefs.accentSeed;

  set accentSeed(int v) {
    if (v == accentSeed) return;
    _prefs.accentSeed = v;
    notifyListeners();
  }

  Color get accentColor => Color(accentSeed);

  bool get useCoverAccent => _prefs.useCoverAccent;

  set useCoverAccent(bool v) {
    if (v == useCoverAccent) return;
    _prefs.useCoverAccent = v;
    notifyListeners();
  }

  /// 由播放器根据封面提取出来的临时主色；为空时使用用户选择的强调色。
  Color? _dynamicAccent;

  Color? get dynamicAccent => useCoverAccent ? _dynamicAccent : null;

  Color get effectiveAccent => dynamicAccent ?? accentColor;

  void setDynamicAccent(Color? color) {
    if (!useCoverAccent) return;
    if (_dynamicAccent == color) return;
    _dynamicAccent = color;
    notifyListeners();
  }

  ThemeData themeFor(Brightness brightness) =>
      AppTheme.build(brightness: brightness, seed: effectiveAccent);

  // --- 语言 ---
  Locale? get locale => _prefs.locale;

  set locale(Locale? v) {
    _prefs.locale = v;
    notifyListeners();
  }

  // --- 内容 ---
  bool get showNsfw => _prefs.showNsfw;

  set showNsfw(bool v) {
    if (v == showNsfw) return;
    _prefs.showNsfw = v;
    notifyListeners();
  }

  bool get blurNsfw => _prefs.blurNsfw;

  set blurNsfw(bool v) {
    if (v == blurNsfw) return;
    _prefs.blurNsfw = v;
    notifyListeners();
  }

  int get gridColumns => _prefs.gridColumns;

  set gridColumns(int v) {
    if (v == gridColumns) return;
    _prefs.gridColumns = v;
    notifyListeners();
  }

  // --- 网络 ---
  bool get autoSelectLine => _prefs.autoSelectLine;

  set autoSelectLine(bool v) {
    if (v == autoSelectLine) return;
    _prefs.autoSelectLine = v;
    _api.preferredIndex = v ? null : _prefs.preferredLineIndex;
    notifyListeners();
  }

  int get preferredLineIndex => _prefs.preferredLineIndex;

  set preferredLineIndex(int v) {
    _prefs.preferredLineIndex = v;
    if (!autoSelectLine) _api.preferredIndex = v;
    notifyListeners();
  }

  String get currentHost => _api.baseUrlHost;

  List<String> get lines => ApiClient.baseUrls;

  // --- 播放 ---
  double get playbackSpeed => _prefs.playbackSpeed;

  set playbackSpeed(double v) {
    _prefs.playbackSpeed = v;
    notifyListeners();
  }

  bool get preferLowQuality => _prefs.preferLowQuality;

  set preferLowQuality(bool v) {
    if (v == preferLowQuality) return;
    _prefs.preferLowQuality = v;
    notifyListeners();
  }

  bool get autoPlayNext => _prefs.autoPlayNext;

  set autoPlayNext(bool v) {
    if (v == autoPlayNext) return;
    _prefs.autoPlayNext = v;
    notifyListeners();
  }

  bool get volumeBoost => _prefs.volumeBoost;

  set volumeBoost(bool v) {
    if (v == volumeBoost) return;
    _prefs.volumeBoost = v;
    notifyListeners();
  }

  int get sleepMinutes => _prefs.sleepMinutes;

  set sleepMinutes(int v) {
    _prefs.sleepMinutes = v;
    notifyListeners();
  }

  // --- 搜索历史 ---
  List<String> get searchHistory => _prefs.searchHistory;

  Future<void> addSearchHistory(String k) async {
    await _prefs.addSearchHistory(k);
    notifyListeners();
  }

  Future<void> removeSearchHistory(String k) async {
    await _prefs.removeSearchHistory(k);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await _prefs.clearSearchHistory();
    notifyListeners();
  }
}
