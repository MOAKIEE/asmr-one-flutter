class SubtitleCue {
  const SubtitleCue(this.startMs, this.endMs, this.text);
  final int startMs;
  final int endMs;
  final String text;
}

class Subtitles {
  static List<SubtitleCue> parse(String source) {
    final text = source
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final cues = <SubtitleCue>[];
    if (text.contains('-->')) {
      for (final block in text.split(RegExp(r'\n\s*\n'))) {
        final lines = block.split('\n');
        final i = lines.indexWhere((line) => line.contains('-->'));
        if (i < 0 || i + 1 >= lines.length || lines.first.startsWith('NOTE')) {
          continue;
        }
        final times = lines[i].split('-->');
        final start = _time(times.first.trim());
        final end = _time(times.last.trim().split(RegExp(r'\s+')).first);
        final caption = _plain(lines.skip(i + 1).join('\n'));
        if (start != null && end != null && end > start && caption.isNotEmpty) {
          cues.add(SubtitleCue(start, end, caption));
        }
      }
    } else {
      final offset =
          int.tryParse(
            RegExp(
                  r'\[offset:([+-]?\d+)\]',
                  caseSensitive: false,
                ).firstMatch(text)?.group(1) ??
                '',
          ) ??
          0;
      final stamp = RegExp(r'\[(\d+:\d{2}(?:[.:]\d{1,3})?)\]');
      for (final line in text.split('\n')) {
        final matches = stamp.allMatches(line).toList();
        if (matches.isEmpty) continue;
        final caption = _plain(line.substring(matches.last.end));
        // Empty timed lines deliberately clear the previous caption.
        for (final match in matches) {
          final raw = match[1]!;
          final normalized = raw.replaceFirstMapped(
            RegExp(r'^(\d+:\d{2}):(\d{1,3})$'),
            (m) => '${m[1]}.${m[2]}',
          );
          final start = _time(normalized);
          if (start != null) {
            cues.add(
              SubtitleCue((start + offset).clamp(0, 1 << 40), 1 << 40, caption),
            );
          }
        }
      }
      cues.sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var i = 0; i < cues.length - 1; i++) {
        cues[i] = SubtitleCue(
          cues[i].startMs,
          cues[i + 1].startMs,
          cues[i].text,
        );
      }
    }
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    if (cues.isEmpty) throw const FormatException('未找到有效的 LRC / SRT / VTT 时间轴');
    return cues;
  }

  static int? _time(String value) {
    final parts = value.replaceAll(',', '.').split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds >= 60 ||
        minutes == null ||
        minutes < 0 ||
        hours == null ||
        hours < 0) {
      return null;
    }
    return ((hours * 3600 + minutes * 60 + seconds) * 1000).round();
  }

  static String _plain(String text) => text
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();

  static int activeIndex(
    List<SubtitleCue> cues,
    int positionMs, {
    int offsetMs = 0,
  }) {
    final time = positionMs - offsetMs;
    var low = 0, high = cues.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (cues[mid].startMs <= time) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found >= 0 && time < cues[found].endMs ? found : -1;
  }
}
