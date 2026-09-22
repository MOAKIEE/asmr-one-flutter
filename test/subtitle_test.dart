import 'package:flutter_test/flutter_test.dart';
import 'package:asmr_one/core/models/subtitle.dart';

void main() {
  test('SRT multi-line captions respect gaps and signed user offset', () {
    final cues = Subtitles.parse(
      '1\r\n00:00:01,200 --> 00:00:03,400\r\nHello\r\nworld\r\n\r\n2\r\n00:00:05,000 --> 00:00:06,000\r\n<i>Bye</i>',
    );
    expect(cues.first.text, 'Hello\nworld');
    expect(cues.last.text, 'Bye');
    expect(Subtitles.activeIndex(cues, 1000), -1);
    expect(Subtitles.activeIndex(cues, 2000), 0);
    expect(Subtitles.activeIndex(cues, 4000), -1);
    expect(Subtitles.activeIndex(cues, 5500, offsetMs: 1000), -1);
    expect(Subtitles.activeIndex(cues, 6500, offsetMs: 1000), 1);
  });
  test('VTT identifiers and settings are parsed without rendering markup', () {
    final cues = Subtitles.parse(
      'WEBVTT\n\nintro\n00:01.000 --> 00:02.000 align:start\n<v speaker>Hello &amp; welcome</v>',
    );
    expect(cues.single.startMs, 1000);
    expect(cues.single.text, 'Hello & welcome');
  });
  test(
    'LRC supports repeated timestamps, metadata offset and timed blank lines',
    () {
      final cues = Subtitles.parse(
        '[ar:Artist]\n[offset:-200]\n[00:01.20][00:03.400]Hello\n[00:05.00]\n[00:06.000]End',
      );
      expect(cues.map((c) => c.startMs), [1000, 3200, 4800, 5800]);
      expect(cues[1].endMs, 4800);
      expect(cues[2].text, '');
    },
  );
  test('malformed subtitle input is rejected', () {
    expect(() => Subtitles.parse('not a subtitle'), throwsFormatException);
    expect(
      () => Subtitles.parse('00:00:03 --> 00:00:01\nWrong'),
      throwsFormatException,
    );
  });
}
