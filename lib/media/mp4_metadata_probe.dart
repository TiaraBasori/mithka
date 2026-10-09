//
//  mp4_metadata_probe.dart
//
//  Codec and frame rate for a downloaded video. TDLib reports duration,
//  dimensions and size but not the codec, and the player only knows it while
//  playing, so the media metadata sheet reads both straight from the file's
//  ISO-BMFF boxes.
//
//  The walk never trusts a box size: every read is clamped to the containing
//  box, so a truncated or partial download ends in a null row, not a crash.
//

import 'dart:io';

/// The first video track's codec, and its average frame rate when the sample
/// table is complete enough to derive one.
class Mp4VideoTrack {
  const Mp4VideoTrack({required this.codec, this.frameRate});

  /// Display name, e.g. H.264.
  final String codec;
  final double? frameRate;
}

/// A box's payload range, from just after its header to its end.
typedef _BoxPayload = ({int start, int end});

/// Reads the first video track of an ISO-BMFF file (mp4/m4v/mov/3gp), or null
/// when [path] is not one, is still downloading, or its sample table is
/// unreadable. Only box headers and two small tables are read, so the cost is
/// a handful of seeks whatever the file size.
Future<Mp4VideoTrack?> probeMp4VideoTrack(String path) async {
  RandomAccessFile? handle;
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length < 16) return null;
    handle = await file.open();
    final reader = _BoxReader(handle, length);
    final moov = await reader.child(0, length, 'moov');
    if (moov == null) return null;
    for (final trak in await reader.childrenOf(moov, only: 'trak')) {
      final track = await _videoTrack(reader, trak.$2);
      if (track != null) return track;
    }
    return null;
  } catch (_) {
    // A race with a delete, a permissions edge, a device pulling the file: the
    // probe is a nicety, so it fails closed.
    return null;
  } finally {
    await handle?.close();
  }
}

Future<Mp4VideoTrack?> _videoTrack(_BoxReader reader, _BoxPayload trak) async {
  final mdia = await reader.child(trak.start, trak.end, 'mdia');
  if (mdia == null) return null;
  final hdlr = await reader.child(mdia.start, mdia.end, 'hdlr');
  if (hdlr == null) return null;
  // version/flags(4) + pre_defined(4), then the handler type.
  final hdlrBytes = await reader.read(hdlr.start, 12);
  if (hdlrBytes == null || _ascii(hdlrBytes, 8, 4) != 'vide') return null;
  final codec = await _codec(reader, mdia);
  if (codec == null) return null;
  return Mp4VideoTrack(codec: codec, frameRate: await _frameRate(reader, mdia));
}

/// stsd's first sample entry — its format fourcc is the codec.
Future<String?> _codec(_BoxReader reader, _BoxPayload mdia) async {
  final stbl = await _stbl(reader, mdia);
  if (stbl == null) return null;
  final stsd = await reader.child(stbl.start, stbl.end, 'stsd');
  if (stsd == null) return null;
  // version/flags(4) + entry_count(4), then the first entry's size(4)+format(4).
  final bytes = await reader.read(stsd.start, 16);
  if (bytes == null) return null;
  final fourcc = _ascii(bytes, 12, 4);
  if (fourcc.trim().isEmpty) return null;
  return mp4CodecName(fourcc);
}

/// Average frame rate: the sample count spread over the track's duration.
Future<double?> _frameRate(_BoxReader reader, _BoxPayload mdia) async {
  final mdhd = await reader.child(mdia.start, mdia.end, 'mdhd');
  if (mdhd == null) return null;
  // v0: creation(4) modification(4) timescale(4)@12 duration(4)@16
  // v1: creation(8) modification(8) timescale(4)@20 duration(8)@24
  final head = await reader.read(mdhd.start, 32);
  if (head == null) return null;
  final timescale = head[0] == 1 ? _u32(head, 20) : _u32(head, 12);
  final duration = head[0] == 1 ? _u64(head, 24) : _u32(head, 16);
  if (timescale == null ||
      timescale == 0 ||
      duration == null ||
      duration == 0) {
    return null;
  }

  final stbl = await _stbl(reader, mdia);
  if (stbl == null) return null;
  final stts = await reader.child(stbl.start, stbl.end, 'stts');
  if (stts == null) return null;
  final sttsHead = await reader.read(stts.start, 8);
  if (sttsHead == null) return null;
  final entryCount = _u32(sttsHead, 4);
  // A runaway count here is a corrupt box, not a video to parse longer.
  if (entryCount == null || entryCount == 0 || entryCount > 4096) return null;
  final tableLength = entryCount * 8;
  if (stts.start + 8 + tableLength > stts.end) return null;
  final table = await reader.read(stts.start + 8, tableLength);
  if (table == null) return null;
  var samples = 0;
  for (var entry = 0; entry < entryCount; entry++) {
    final count = _u32(table, entry * 8);
    if (count == null) return null;
    samples += count;
  }
  if (samples <= 0) return null;
  return samples / (duration / timescale);
}

Future<_BoxPayload?> _stbl(_BoxReader reader, _BoxPayload mdia) async {
  final minf = await reader.child(mdia.start, mdia.end, 'minf');
  if (minf == null) return null;
  return reader.child(minf.start, minf.end, 'stbl');
}

/// A fourcc's display name, or the raw code uppercased when it is unknown.
String mp4CodecName(String fourcc) => switch (fourcc.toLowerCase()) {
  'avc1' || 'avc3' => 'H.264',
  'hvc1' || 'hev1' => 'HEVC',
  'dvh1' || 'dvhe' => 'Dolby Vision (HEVC)',
  'av01' => 'AV1',
  'vp08' => 'VP8',
  'vp09' => 'VP9',
  'mp4v' => 'MPEG-4',
  's263' => 'H.263',
  'mp4a' => 'AAC',
  'jpeg' => 'JPEG',
  _ => fourcc.toUpperCase(),
};

class _BoxReader {
  _BoxReader(this._handle, this.length);

  final RandomAccessFile _handle;
  final int length;

  Future<List<int>?> read(int offset, int count) async {
    if (offset < 0 || count <= 0 || offset + count > length) return null;
    await _handle.setPosition(offset);
    final bytes = await _handle.read(count);
    return bytes.length == count ? bytes : null;
  }

  /// The payload range of the first direct child of [start, end) with the
  /// given type, or null.
  Future<_BoxPayload?> child(int start, int end, String type) async {
    for (final box in await childrenOf((start: start, end: end))) {
      if (box.$1 == type) return box.$2;
    }
    return null;
  }

  /// Every direct child of [parent], in file order. A bogus size ends the
  /// walk: once one box's length points outside its parent, later siblings
  /// cannot be trusted.
  Future<List<(String, _BoxPayload)>> childrenOf(
    _BoxPayload parent, {
    String? only,
  }) async {
    final found = <(String, _BoxPayload)>[];
    var offset = parent.start;
    while (offset <= parent.end - 8 && found.length < 512) {
      final header = await read(offset, 8);
      if (header == null) break;
      final type = _ascii(header, 4, 4);
      if (!_isBoxType(type)) break;
      var size = _u32(header, 0);
      if (size == null) break;
      var headerSize = 8;
      if (size == 1) {
        final extended = await read(offset + 8, 8);
        final long = extended == null ? null : _u64(extended, 0);
        if (long == null || long < 16) break;
        size = long;
        headerSize = 16;
      } else if (size == 0) {
        // A box size of 0 means "to the end of the file/container".
        size = parent.end - offset;
      }
      if (size < headerSize || size > parent.end - offset) break;
      final payload = (start: offset + headerSize, end: offset + size);
      if (only == null || type == only) found.add((type, payload));
      offset += size;
    }
    return found;
  }
}

bool _isBoxType(String type) {
  if (type.isEmpty) return false;
  for (var index = 0; index < type.length; index++) {
    final code = type.codeUnitAt(index);
    final digit = code >= 0x30 && code <= 0x39;
    final upper = code >= 0x41 && code <= 0x5a;
    final lower = code >= 0x61 && code <= 0x7a;
    if (!digit && !upper && !lower) return false;
  }
  return true;
}

String _ascii(List<int> bytes, int offset, int count) {
  final end = offset + count;
  if (end > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, end));
}

int? _u32(List<int> bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) return null;
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int? _u64(List<int> bytes, int offset) {
  final high = _u32(bytes, offset);
  final low = _u32(bytes, offset + 4);
  if (high == null || low == null) return null;
  return (high << 32) | low;
}
