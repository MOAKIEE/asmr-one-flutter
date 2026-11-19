import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/api/update_client.dart';
import '../core/app_info.dart';
import '../core/models/release.dart';
import '../core/storage/app_prefs.dart';

/// 更新检查当前所处状态。
enum UpdateStatus { idle, checking, upToDate, available, error }

/// 单次检查调用的返回结果。
enum UpdateCheckOutcome { skipped, upToDate, available, failed }

/// 应用更新检查状态。
class UpdateState extends ChangeNotifier {
  UpdateState(
    this._prefs, {
    UpdateClient? client,
    Future<String> Function()? versionLoader,
    DateTime Function()? now,
    Duration? autoCheckCooldown,
    String? initialVersion,
  }) : _client = client ?? UpdateClient(),
       _versionLoader = versionLoader ?? AppInfo.resolveVersion,
       _now = now ?? DateTime.now,
       _autoCheckCooldown = autoCheckCooldown ?? const Duration(hours: 6),
       _currentVersion = (initialVersion != null && initialVersion.trim().isNotEmpty)
           ? initialVersion.trim()
           : AppInfo.fallbackVersion,
       _versionLoaded = initialVersion != null && initialVersion.trim().isNotEmpty;

  final AppPrefs _prefs;
  final UpdateClient _client;
  final Future<String> Function() _versionLoader;
  final DateTime Function() _now;
  final Duration _autoCheckCooldown;

  String _currentVersion;
  bool _versionLoaded;
  Future<void>? _versionLoading;
  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _latestRelease;
  UpdateErrorKind? _lastError;
  bool _promptedThisSession = false;
  Future<UpdateCheckOutcome>? _inFlight;
  bool _activeCheckManual = false;
  bool _disposed = false;

  /// 当前应用版本号（例如 `1.2.0`）。
  String get currentVersion => _currentVersion;

  UpdateStatus get status => _status;

  bool get checking => _status == UpdateStatus.checking;

  ReleaseInfo? get latestRelease => _latestRelease;

  UpdateErrorKind? get lastError => _lastError;

  bool get autoCheckUpdate => _prefs.autoCheckUpdate;

  set autoCheckUpdate(bool v) {
    if (v == autoCheckUpdate) return;
    _prefs.autoCheckUpdate = v;
    _notify();
  }

  String? get ignoredVersion => _prefs.ignoredUpdateVersion;

  bool get hasUpdate {
    final release = _latestRelease;
    if (release == null) return false;
    return AppVersion.isNewer(
      latest: release.tagName,
      current: _currentVersion,
    );
  }

  bool isIgnored(String tagName) {
    final ignored = ignoredVersion;
    if (ignored == null) return false;
    return AppVersion.normalizeLabel(ignored) ==
        AppVersion.normalizeLabel(tagName);
  }

  /// 是否存在未被用户忽略的新版本。
  bool get hasUnignoredUpdate =>
      hasUpdate && !isIgnored(_latestRelease!.tagName);

  /// 启动自动检查发现新版本且本会话尚未自动弹出过提醒。
  bool get shouldAutoPrompt => hasUnignoredUpdate && !_promptedThisSession;

  /// 异步读取安装包版本号（仅执行一次，重复调用共享同一次加载）。
  Future<void> initVersion() async {
    if (_versionLoaded) return;
    final pending = _versionLoading;
    if (pending != null) return pending;

    final future = () async {
      final loaded = (await _versionLoader()).trim();
      _versionLoaded = true;
      if (loaded.isNotEmpty && loaded != _currentVersion) {
        _currentVersion = loaded;
        // 版本号变化后同步刷新状态判定。
        if (_latestRelease != null) {
          _status = hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate;
        }
        _notify();
      }
    }();
    _versionLoading = future;
    try {
      await future;
    } finally {
      _versionLoading = null;
    }
  }

  /// 执行更新检查。
  ///
  /// - `manual == false`（启动静默检查）：遵循开关与冷却时间，失败不打扰用户。
  /// - `manual == true`（用户主动点击）：忽略冷却时间与已忽略版本，返回明确结果。
  Future<UpdateCheckOutcome> checkForUpdates({bool manual = false}) {
    final existing = _inFlight;
    if (existing != null) {
      if (manual) _activeCheckManual = true;
      return existing;
    }

    _activeCheckManual = manual;
    late final Future<UpdateCheckOutcome> future;
    future = _runCheck(manual: manual).whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _activeCheckManual = false;
      }
    });
    _inFlight = future;
    return future;
  }

  Future<UpdateCheckOutcome> _runCheck({required bool manual}) async {
    await initVersion();
    if (_disposed) return UpdateCheckOutcome.skipped;

    if (!manual && !_activeCheckManual) {
      if (!autoCheckUpdate) return UpdateCheckOutcome.skipped;
      final lastMs = _prefs.lastUpdateCheckMs;
      if (lastMs > 0) {
        final elapsed = _now().millisecondsSinceEpoch - lastMs;
        if (elapsed >= 0 && elapsed < _autoCheckCooldown.inMilliseconds) {
          return UpdateCheckOutcome.skipped;
        }
      }
    }

    final previousStatus = _status;
    _status = UpdateStatus.checking;
    _lastError = null;
    _notify();

    try {
      final release = await _client.fetchLatestRelease();
      if (_disposed) return UpdateCheckOutcome.skipped;

      _prefs.lastUpdateCheckMs = _now().millisecondsSinceEpoch;
      _latestRelease = release;

      if (release != null &&
          AppVersion.isNewer(
            latest: release.tagName,
            current: _currentVersion,
          )) {
        _status = UpdateStatus.available;
        _notify();
        return UpdateCheckOutcome.available;
      }

      _status = UpdateStatus.upToDate;
      _notify();
      return UpdateCheckOutcome.upToDate;
    } on UpdateCheckException catch (e) {
      if (_disposed) return UpdateCheckOutcome.failed;
      if (_activeCheckManual) {
        _lastError = e.kind;
        _status = UpdateStatus.error;
      } else {
        // 静默自动检查失败时保留先前有效状态，不误报错误。
        _status = previousStatus == UpdateStatus.checking
            ? UpdateStatus.idle
            : previousStatus;
      }
      _notify();
      return UpdateCheckOutcome.failed;
    } catch (_) {
      if (_disposed) return UpdateCheckOutcome.failed;
      if (_activeCheckManual) {
        _lastError = UpdateErrorKind.unknown;
        _status = UpdateStatus.error;
      } else {
        _status = previousStatus == UpdateStatus.checking
            ? UpdateStatus.idle
            : previousStatus;
      }
      _notify();
      return UpdateCheckOutcome.failed;
    }
  }

  void markPrompted() {
    if (_promptedThisSession) return;
    _promptedThisSession = true;
  }

  Future<void> ignoreRelease(String tagName) async {
    final normalized = AppVersion.normalizeLabel(tagName);
    if (normalized.isEmpty) return;
    _prefs.ignoredUpdateVersion = normalized;
    _promptedThisSession = true;
    _notify();
  }

  Future<void> clearIgnoredVersion() async {
    if (_prefs.ignoredUpdateVersion == null) return;
    _prefs.ignoredUpdateVersion = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 兼容未挂载 [UpdateState] 的独立组件测试环境。
extension UpdateStateContext on BuildContext {
  UpdateState? watchUpdateOrNull() {
    try {
      return watch<UpdateState>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  UpdateState? readUpdateOrNull() {
    try {
      return read<UpdateState>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}
