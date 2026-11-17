import 'dart:async';

/// 各类展示格式化工具。
class Fmt {
  const Fmt._();

  /// 秒 -> `12:34` / `1:02:03`。
  static String duration(num? seconds) {
    final total = (seconds ?? 0).round();
    if (total <= 0) return '--:--';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// 毫秒 -> 时间轴文案。
  static String position(Duration d) => duration(d.inMilliseconds / 1000);

  /// 大数字：中文/日文 `1.2万`，英文 `1.2k` / `1.2M`。
  static String count(int n, {String languageCode = 'zh'}) {
    if (languageCode == 'en') {
      if (n >= 1000000000) {
        return '${(n / 1000000000).toStringAsFixed(1)}B';
      }
      if (n >= 1000000) {
        return '${(n / 1000000).toStringAsFixed(1)}M';
      }
      if (n >= 1000) {
        final v = n / 1000;
        return '${v >= 100 ? v.round() : v.toStringAsFixed(1)}k';
      }
      return '$n';
    }
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) {
      final v = n / 10000;
      return '${v >= 100 ? v.round() : v.toStringAsFixed(1)}万';
    }
    if (n >= 1000) {
      final v = n / 1000;
      return '${v >= 100 ? v.round() : v.toStringAsFixed(1)}k';
    }
    return '$n';
  }

  /// 日元价格。0 视为免费。
  static String price(int yen, String freeLabel) {
    if (yen <= 0) return freeLabel;
    final s = yen.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '¥${buf.toString()}';
  }

  /// `2026-06-27` -> `2026/06/27`。
  static String date(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    return raw.replaceAll('-', '/');
  }

  /// 相对时间：按语言返回 `3 天前` / `3d ago` / `3日前`。
  static String relative(
    String? raw, {
    String? languageCode,
    String? today,
    String? yesterday,
  }) {
    if (raw == null || raw.isEmpty) return '—';
    final d = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    if (d == null) return raw;
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    switch (languageCode) {
      case 'en':
        if (diff <= 0) return today ?? 'Today';
        if (diff == 1) return yesterday ?? 'Yesterday';
        if (diff < 30) return '${diff}d ago';
        if (diff < 365) return '${(diff / 30).floor()}mo ago';
        return '${(diff / 365).floor()}y ago';
      case 'ja':
        if (diff <= 0) return today ?? '今日';
        if (diff == 1) return yesterday ?? '昨日';
        if (diff < 30) return '$diff 日前';
        if (diff < 365) return '${(diff / 30).floor()} か月前';
        return '${(diff / 365).floor()} 年前';
      default:
        if (diff <= 0) return today ?? '今天';
        if (diff == 1) return yesterday ?? '昨天';
        if (diff < 30) return '$diff 天前';
        if (diff < 365) return '${(diff / 30).floor()} 个月前';
        return '${(diff / 365).floor()} 年前';
    }
  }

  /// 字节 -> `1.2 GB`。
  static String size(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  /// 评分保留 1~2 位小数。
  static String rating(double v) {
    if (v <= 0) return '—';
    return v.toStringAsFixed(v == v.roundToDouble() ? 1 : 2);
  }

  /// 截断过长的标题。
  static String ellipsis(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// 从文件名中去掉扩展名，作为曲目标题展示。
  static String stripExt(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return name;
    final ext = name.substring(i + 1).toLowerCase();
    const audio = {'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma'};
    return audio.contains(ext) ? name.substring(0, i) : name;
  }

  /// 从文件名中提取前导序号，用于曲目排序展示。
  static String truncateMiddle(String s, int max) {
    if (s.length <= max) return s;
    final half = (max - 1) ~/ 2;
    return '${s.substring(0, half)}…${s.substring(s.length - half)}';
  }
}

/// 简单的防抖工具，用于搜索框等输入场景。
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 350)});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
