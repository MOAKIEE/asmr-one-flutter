import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用偏好设置（基于 shared_preferences）。
///
/// 所有键都集中在此，避免散落在各处的字符串字面量。
class AppPrefs {
  AppPrefs(this._sp);

  final SharedPreferences _sp;

  static Future<AppPrefs> load() async =>
      AppPrefs(await SharedPreferences.getInstance());

  // --- keys ---
  static const _kToken = 'auth.token';
  static const _kLocale = 'ui.locale';
  static const _kThemeMode = 'ui.themeMode';
  static const _kAccent = 'ui.accentSeed';
  static const _kUseCoverAccent = 'ui.useCoverAccent';
  static const _kBlurNsfw = 'ui.blurNsfw';
  static const _kShowNsfw = 'content.showNsfw';
  static const _kGridColumns = 'ui.gridColumns';
  static const _kAutoLine = 'net.autoLine';
  static const _kLineIndex = 'net.lineIndex';
  static const _kSearchHistory = 'search.history';
  static const _kPlaybackSpeed = 'player.speed';
  static const _kLowQuality = 'player.lowQuality';
  static const _kAutoPlayNext = 'player.autoPlayNext';
  static const _kVolumeBoost = 'player.volumeBoost';
  static const _kSleepMinutes = 'player.sleepMinutes';
  static const _kFirstRun = 'app.firstRun';
  static const _kTagCatalogVersion = 'tag.catalogVersion';

  // --- 鉴权 ---
  String? get token {
    final t = _sp.getString(_kToken);
    return (t == null || t.isEmpty) ? null : t;
  }

  set token(String? value) {
    if (value == null || value.isEmpty) {
      _sp.remove(_kToken);
    } else {
      _sp.setString(_kToken, value);
    }
  }

  // --- 界面语言 ---
  /// `null` 表示跟随系统。
  Locale? get locale {
    final v = _sp.getString(_kLocale);
    if (v == null || v.isEmpty || v == 'system') return null;
    final parts = v.split('-');
    return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }

  set locale(Locale? value) {
    if (value == null) {
      _sp.setString(_kLocale, 'system');
    } else {
      _sp.setString(
        _kLocale,
        value.countryCode == null
            ? value.languageCode
            : '${value.languageCode}-${value.countryCode}',
      );
    }
  }

  // --- 主题 ---
  ThemeMode get themeMode {
    switch (_sp.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  set themeMode(ThemeMode mode) => _sp.setString(_kThemeMode, mode.name);

  int get accentSeed => _sp.getInt(_kAccent) ?? 0xFF7C5CFF;

  set accentSeed(int v) => _sp.setInt(_kAccent, v);

  /// 是否使用当前播放作品封面取色作为强调色。
  bool get useCoverAccent => _sp.getBool(_kUseCoverAccent) ?? false;

  set useCoverAccent(bool v) => _sp.setBool(_kUseCoverAccent, v);

  // --- 内容偏好 ---
  /// 列表 / 详情中对 NSFW 封面打码。
  bool get blurNsfw => _sp.getBool(_kBlurNsfw) ?? true;

  set blurNsfw(bool v) => _sp.setBool(_kBlurNsfw, v);

  /// 首页与浏览默认是否包含 18 禁内容。
  bool get showNsfw => _sp.getBool(_kShowNsfw) ?? true;

  set showNsfw(bool v) => _sp.setBool(_kShowNsfw, v);

  int get gridColumns => _sp.getInt(_kGridColumns) ?? 2;

  set gridColumns(int v) => _sp.setInt(_kGridColumns, v.clamp(1, 4));

  // --- 网络 ---
  bool get autoSelectLine => _sp.getBool(_kAutoLine) ?? true;

  set autoSelectLine(bool v) => _sp.setBool(_kAutoLine, v);

  int get preferredLineIndex => _sp.getInt(_kLineIndex) ?? 0;

  set preferredLineIndex(int v) => _sp.setInt(_kLineIndex, v);

  // --- 搜索历史 ---
  List<String> get searchHistory =>
      _sp.getStringList(_kSearchHistory) ?? const <String>[];

  Future<void> addSearchHistory(String keyword, {int max = 20}) async {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final list = [...searchHistory]..removeWhere((e) => e == k);
    list.insert(0, k);
    await _sp.setStringList(
      _kSearchHistory,
      list.take(max).toList(growable: false),
    );
  }

  Future<void> removeSearchHistory(String keyword) async {
    final list = [...searchHistory]..remove(keyword);
    await _sp.setStringList(_kSearchHistory, list);
  }

  Future<void> clearSearchHistory() => _sp.remove(_kSearchHistory);

  // --- 播放器 ---
  double get playbackSpeed {
    final v = _sp.getDouble(_kPlaybackSpeed) ?? 1.0;
    return v <= 0 ? 1.0 : v;
  }

  set playbackSpeed(double v) => _sp.setDouble(_kPlaybackSpeed, v);

  bool get preferLowQuality => _sp.getBool(_kLowQuality) ?? false;

  set preferLowQuality(bool v) => _sp.setBool(_kLowQuality, v);

  bool get autoPlayNext => _sp.getBool(_kAutoPlayNext) ?? true;

  set autoPlayNext(bool v) => _sp.setBool(_kAutoPlayNext, v);

  bool get volumeBoost => _sp.getBool(_kVolumeBoost) ?? false;

  set volumeBoost(bool v) => _sp.setBool(_kVolumeBoost, v);

  /// 上次使用的定时关闭分钟数，0 表示未启用。
  int get sleepMinutes => _sp.getInt(_kSleepMinutes) ?? 0;

  set sleepMinutes(int v) => _sp.setInt(_kSleepMinutes, v);

  // --- 其它 ---
  bool get isFirstRun => _sp.getBool(_kFirstRun) ?? true;

  set isFirstRun(bool v) => _sp.setBool(_kFirstRun, v);

  int get tagCatalogVersion => _sp.getInt(_kTagCatalogVersion) ?? 0;

  set tagCatalogVersion(int v) => _sp.setInt(_kTagCatalogVersion, v);

  /// 导出全部偏好（用于设置页展示 / 调试）。
  String dump() => jsonEncode({
    'locale': _sp.getString(_kLocale),
    'themeMode': _sp.getString(_kThemeMode),
    'hasToken': token != null,
  });

  Future<void> clearAll() async {
    final keep = token;
    await _sp.clear();
    if (keep != null) await _sp.setString(_kToken, keep);
  }
}
