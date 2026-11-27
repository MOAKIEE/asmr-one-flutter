import 'package:mimori/core/models/subtitle_matcher.dart';
import 'package:mimori/core/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

TrackNode _folder(String title, List<TrackNode> children) =>
    TrackNode(type: 'folder', title: title, children: children);

TrackNode _audio(String title, {String? hash}) =>
    TrackNode(type: 'audio', title: title, hash: hash);

TrackNode _sub(String title, {String? hash}) => TrackNode(
  type: 'text',
  title: title,
  hash: hash,
  mediaDownloadUrl: 'https://example.invalid/${hash ?? title}',
);

void main() {
  group('SubtitleMatcher design table examples', () {
    test('matches same-directory same-name chapter LRC', () {
      final index = WorkTrackIndex.fromNodes(1, [
        _folder('本篇', [
          _audio('01 耳かき.mp3', hash: '1/a1'),
          _audio('02 添い寝.mp3', hash: '1/a2'),
          _sub('01 耳かき.lrc', hash: '1/s1'),
          _sub('02 添い寝.lrc', hash: '1/s2'),
        ]),
      ]);

      final audio = index.findAudio(
        workId: 1,
        hash: '1/a1',
        folderLabel: '本篇',
        title: '01 耳かき.mp3',
      )!;
      final res = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'zh-hans',
      );
      expect(res.outcome, SubtitleMatchOutcome.matched);
      expect(res.attachment!.hash, '1/s1');
    });

    test('normalizes format/language folders and fullwidth numbers while keeping Disc 2 group', () {
      final index = WorkTrackIndex.fromNodes(2, [
        _folder('Disc 2', [
          _folder('MP3', [_audio('02 おやすみ.mp3', hash: '2/a2')]),
        ]),
        _folder('字幕', [
          _folder('简中', [
            _folder('Disc 2', [_sub('０２ おやすみ.srt', hash: '2/s2')]),
          ]),
        ]),
      ]);

      final audio = index.findAudio(
        workId: 2,
        hash: '2/a2',
        folderLabel: 'Disc 2 / MP3',
        title: '02 おやすみ.mp3',
      )!;
      final res = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'zh-hans',
      );
      expect(res.outcome, SubtitleMatchOutcome.matched);
      expect(res.attachment!.hash, '2/s2');
    });

    test('rejects group conflict between 特典 and 本篇', () {
      final index = WorkTrackIndex.fromNodes(3, [
        _folder('特典', [_audio('01.wav', hash: '3/a1')]),
        _folder('本篇', [_sub('01.srt', hash: '3/s1')]),
      ]);

      final audio = index.findAudio(
        workId: 3,
        hash: '3/a1',
        folderLabel: '特典',
        title: '01.wav',
      )!;
      final res = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'zh-hans',
      );
      expect(res.outcome, SubtitleMatchOutcome.noMatch);
    });

    test('rejects version conflict between 无声效 and 有声效', () {
      final index = WorkTrackIndex.fromNodes(4, [
        _folder('无声效', [_audio('02.wav', hash: '4/a2')]),
        _folder('有声效', [_sub('02.vtt', hash: '4/s2')]),
      ]);

      final audio = index.findAudio(
        workId: 4,
        hash: '4/a2',
        folderLabel: '无声效',
        title: '02.wav',
      )!;
      final res = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'zh-hans',
      );
      expect(res.outcome, SubtitleMatchOutcome.noMatch);
    });
  });

  group('SubtitleMatcher multi-disc, multi-language, near-title and edge cases', () {
    test('separates same-named tracks across Disc 1 and Disc 2 and refuses cross-disc bare match', () {
      final index = WorkTrackIndex.fromNodes(10, [
        _folder('Disc 1', [_audio('01 序章.mp3', hash: '10/d1')]),
        _folder('Disc 2', [_audio('01 序章.mp3', hash: '10/d2')]),
        _folder('字幕', [
          _folder('Disc 1', [_sub('01 序章.lrc', hash: '10/s1')]),
          _folder('Disc 2', [_sub('01 序章.lrc', hash: '10/s2')]),
        ]),
      ]);

      final d1 = index.findAudio(
        workId: 10,
        hash: '10/d1',
        folderLabel: 'Disc 1',
        title: '01 序章.mp3',
      )!;
      final d2 = index.findAudio(
        workId: 10,
        hash: '10/d2',
        folderLabel: 'Disc 2',
        title: '01 序章.mp3',
      )!;

      expect(
        SubtitleMatcher.match(
          index: index,
          audio: d1,
          preferredLanguage: 'zh-hans',
        ).attachment?.hash,
        '10/s1',
      );
      expect(
        SubtitleMatcher.match(
          index: index,
          audio: d2,
          preferredLanguage: 'zh-hans',
        ).attachment?.hash,
        '10/s2',
      );

      // Missing disc subfolder in subtitles: must not guess across discs.
      final flatSubIndex = WorkTrackIndex.fromNodes(11, [
        _folder('Disc 1', [_audio('01.mp3', hash: '11/d1')]),
        _folder('Disc 2', [_audio('01.mp3', hash: '11/d2')]),
        _folder('字幕', [_sub('01.lrc', hash: '11/s')]),
      ]);
      expect(
        SubtitleMatcher.match(
          index: flatSubIndex,
          audio: flatSubIndex.audioTracks.first,
          preferredLanguage: 'zh-hans',
        ).outcome,
        SubtitleMatchOutcome.noMatch,
      );
    });

    test('prefers app display language and reports ambiguous when top priority ties', () {
      final index = WorkTrackIndex.fromNodes(20, [
        _folder('MP3', [_audio('01 耳かき.mp3', hash: '20/a1')]),
        _folder('字幕', [
          _folder('简中', [_sub('01 耳かき.srt', hash: '20/zh')]),
          _folder('日文', [_sub('01 耳かき.srt', hash: '20/ja')]),
        ]),
      ]);
      final audio = index.audioTracks.single;

      final zhMatch = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'zh-hans',
      );
      expect(zhMatch.outcome, SubtitleMatchOutcome.matched);
      expect(zhMatch.attachment!.hash, '20/zh');

      final jaMatch = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'ja',
      );
      expect(jaMatch.outcome, SubtitleMatchOutcome.matched);
      expect(jaMatch.attachment!.hash, '20/ja');

      // App language is English: neither zh nor ja matches, so it is ambiguous.
      final enMatch = SubtitleMatcher.match(
        index: index,
        audio: audio,
        preferredLanguage: 'en',
      );
      expect(enMatch.outcome, SubtitleMatchOutcome.ambiguous);
      expect(enMatch.candidates, hasLength(2));
    });

    test('handles near titles, chapter-prefix differences, and rejects mismatched descriptive titles', () {
      final index = WorkTrackIndex.fromNodes(30, [
        _folder('本篇', [
          _audio('01_耳かき.mp3', hash: '30/a1'),
          _audio('02 耳かき.mp3', hash: '30/a2'),
          _audio('03 添い寝.mp3', hash: '30/a3'),
          _sub('Track 01 - 耳かき.mp3.vtt', hash: '30/s1'),
          _sub('02 耳かき 续.lrc', hash: '30/s2_near'),
          _sub('03.lrc', hash: '30/s3_num'),
        ]),
      ]);

      // Track 01 - 耳かき.mp3.vtt matches 01_耳かき.mp3 via chapter + matching title.
      final r1 = SubtitleMatcher.match(
        index: index,
        audio: index.audioTracks[0],
        preferredLanguage: 'zh-hans',
      );
      expect(r1.outcome, SubtitleMatchOutcome.matched);
      expect(r1.attachment!.hash, '30/s1');

      // Near title `02 耳かき 续.lrc` differs from `02 耳かき.mp3` -> must not match.
      final r2 = SubtitleMatcher.match(
        index: index,
        audio: index.audioTracks[1],
        preferredLanguage: 'zh-hans',
      );
      expect(r2.outcome, SubtitleMatchOutcome.noMatch);

      // Unique chapter number `03` with bare `03.lrc` in same group matches.
      final r3 = SubtitleMatcher.match(
        index: index,
        audio: index.audioTracks[2],
        preferredLanguage: 'zh-hans',
      );
      expect(r3.outcome, SubtitleMatchOutcome.matched);
      expect(r3.attachment!.hash, '30/s3_num');
    });

    test('preserves left/right channel and SE markers and blocks non-unique bare chapter numbers', () {
      final index = WorkTrackIndex.fromNodes(40, [
        _folder('本篇', [
          _audio('01 左声道.mp3', hash: '40/left'),
          _audio('01 右声道.mp3', hash: '40/right'),
          _sub('01.lrc', hash: '40/bare'),
        ]),
      ]);

      // Two tracks share chapter 1 in the same group, so bare `01.lrc` cannot match either.
      expect(
        SubtitleMatcher.match(
          index: index,
          audio: index.audioTracks[0],
          preferredLanguage: 'zh-hans',
        ).outcome,
        SubtitleMatchOutcome.noMatch,
      );
      expect(
        SubtitleMatcher.match(
          index: index,
          audio: index.audioTracks[1],
          preferredLanguage: 'zh-hans',
        ).outcome,
        SubtitleMatchOutcome.noMatch,
      );
    });

    test('locates audio by folder and title when hash is absent', () {
      final index = WorkTrackIndex.fromNodes(50, [
        _folder('正篇', [_audio('01 晚安.mp3')]),
      ]);
      final found = index.findAudio(
        workId: 50,
        hash: null,
        folderLabel: '正篇',
        title: '01 晚安.mp3',
      );
      expect(found, isNotNull);
      expect(found!.folderPath, ['正篇']);
    });
  });
}
