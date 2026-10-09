import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/mp4_metadata_probe.dart';

List<int> _u32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

List<int> _box(String type, List<int> payload) => [
  ..._u32(8 + payload.length),
  ...type.codeUnits,
  ...payload,
];

/// A box whose size needs the 64-bit form: size32(4)=1 + type(4) + largesize(8).
List<int> _largeBox(String type, List<int> payload) => [
  ..._u32(1),
  ...type.codeUnits,
  ..._u32(0),
  ..._u32(16 + payload.length),
  ...payload,
];

List<int> _mdhd({
  int version = 0,
  int timescale = 600,
  int duration = 300,
  int pad = 12,
}) => _box('mdhd', [
  version,
  0,
  0,
  0, // version + flags
  if (version == 0) ...[
    ..._u32(0), // creation
    ..._u32(0), // modification
    ..._u32(timescale),
    ..._u32(duration),
  ] else ...[
    ..._u32(0),
    ..._u32(0), // creation (64-bit)
    ..._u32(0),
    ..._u32(0), // modification (64-bit)
    ..._u32(timescale),
    ..._u32(duration >> 32),
    ..._u32(duration & 0xffffffff),
  ],
  ...List<int>.filled(pad, 0),
]);

List<int> _hdlr(String handler) => _box('hdlr', [
  0,
  0,
  0,
  0, // version + flags
  ..._u32(0), // pre_defined
  ...handler.codeUnits,
  0,
  0,
  0,
  0,
]);

List<int> _stsd(String fourcc) => _box('stsd', [
  0,
  0,
  0,
  0, // version + flags
  ..._u32(1), // entry_count
  ..._u32(16), // first entry size
  ...fourcc.codeUnits,
]);

List<int> _stts(List<(int, int)> entries) => _box('stts', [
  0,
  0,
  0,
  0,
  ..._u32(entries.length),
  // The table interleaves: sample_count then sample_delta, per entry.
  for (final entry in entries) ...[..._u32(entry.$1), ..._u32(entry.$2)],
]);

List<int> _trak({
  String handler = 'vide',
  String codec = 'avc1',
  int timescale = 600,
  int duration = 300,
  List<(int, int)> stts = const [(15, 20)],
  int mdhdVersion = 0,
  bool withStts = true,
}) => _box('trak', [
  ..._box('mdia', [
    ..._mdhd(version: mdhdVersion, timescale: timescale, duration: duration),
    ..._hdlr(handler),
    ..._box('minf', [
      ..._box('stbl', [..._stsd(codec), if (withStts) ..._stts(stts)]),
    ]),
  ]),
]);

List<int> _mp4({
  List<List<int>>? traks,
  bool longSize = false,
  bool moovFirst = false,
}) {
  final tracks = traks ?? [_trak()];
  final moov = _box('moov', [for (final trak in tracks) ...trak]);
  final media = longSize
      ? _largeBox('mdat', List<int>.filled(64, 7))
      : _box('mdat', List<int>.filled(64, 7));
  // moov before mdat when asked, otherwise the classic metadata-at-the-end
  // file a phone records.
  final boxes = <List<int>>[if (moovFirst) moov, media, if (!moovFirst) moov];
  return [
    ..._box('ftyp', [...'isom'.codeUnits, ..._u32(0), ...'isom'.codeUnits]),
    for (final box in boxes) ...box,
  ];
}

Future<String> _writeFile(List<int> bytes, {String name = 'clip.mp4'}) async {
  final directory = await Directory.systemTemp.createTemp('mithka-mp4-probe');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  test('reads the codec and frame rate of an mdat-first file', () async {
    final path = await _writeFile(_mp4());
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'H.264');
    expect(track?.frameRate, closeTo(30, 0.001));
  });

  test('reads a file whose moov sits at the front', () async {
    final path = await _writeFile(_mp4(moovFirst: true));
    expect((await probeMp4VideoTrack(path))?.codec, 'H.264');
  });

  test('walks past a 64-bit box header', () async {
    final path = await _writeFile(_mp4(longSize: true));
    expect((await probeMp4VideoTrack(path))?.codec, 'H.264');
  });

  test('skips an audio track and reads the video track after it', () async {
    final path = await _writeFile(
      _mp4(
        traks: [
          _trak(handler: 'soun', codec: 'mp4a', withStts: false),
          _trak(codec: 'hvc1', timescale: 900, duration: 450, stts: [(30, 30)]),
        ],
      ),
    );
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'HEVC');
    expect(track?.frameRate, closeTo(60, 0.001));
  });

  test('handles the 64-bit mdhd time fields', () async {
    final path = await _writeFile(_mp4(traks: [_trak(mdhdVersion: 1)]));
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'H.264');
    expect(track?.frameRate, closeTo(30, 0.001));
  });

  test('reports the codec without a frame rate when stts is missing', () async {
    final path = await _writeFile(_mp4(traks: [_trak(withStts: false)]));
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'H.264');
    expect(track?.frameRate, isNull);
  });

  test('sums every stts entry', () async {
    final path = await _writeFile(
      _mp4(
        traks: [
          _trak(duration: 600, stts: [(10, 20), (20, 20)]),
        ],
      ),
    );
    // 30 samples over one second.
    expect((await probeMp4VideoTrack(path))?.frameRate, closeTo(30, 0.001));
  });

  test('fails closed on a truncated download', () async {
    final whole = _mp4();
    final path = await _writeFile(whole.sublist(0, whole.length - 12));
    expect(await probeMp4VideoTrack(path), isNull);
  });

  test('fails closed on files that are not ISO-BMFF', () async {
    final junk = await _writeFile([
      ...'1A45DFA3'.codeUnits,
      ...List<int>.filled(64, 0),
    ], name: 'clip.webm');
    expect(await probeMp4VideoTrack(junk), isNull);

    final tiny = await _writeFile(const [0, 0, 0, 8], name: 'empty.mp4');
    expect(await probeMp4VideoTrack(tiny), isNull);

    expect(await probeMp4VideoTrack('/no/such/file.mp4'), isNull);
  });

  test('names the known sample formats', () {
    expect(mp4CodecName('avc3'), 'H.264');
    expect(mp4CodecName('hev1'), 'HEVC');
    expect(mp4CodecName('av01'), 'AV1');
    expect(mp4CodecName('vp09'), 'VP9');
    expect(mp4CodecName('zzzz'), 'ZZZZ');
  });
}
