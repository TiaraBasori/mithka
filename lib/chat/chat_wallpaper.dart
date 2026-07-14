import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/td_client.dart';

enum ChatWallpaperKind { preset, image }

@immutable
class ChatWallpaper {
  const ChatWallpaper.preset(this.presetId)
    : kind = ChatWallpaperKind.preset,
      imagePath = null;

  const ChatWallpaper.image(this.imagePath)
    : kind = ChatWallpaperKind.image,
      presetId = null;

  final ChatWallpaperKind kind;
  final String? presetId;
  final String? imagePath;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (presetId != null) 'preset_id': presetId,
    if (imagePath != null) 'image_path': imagePath,
  };

  static ChatWallpaper? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'];
    if (kind == ChatWallpaperKind.preset.name) {
      final id = value['preset_id'];
      return id is String && chatWallpaperPreset(id) != null
          ? ChatWallpaper.preset(id)
          : null;
    }
    if (kind == ChatWallpaperKind.image.name) {
      final path = value['image_path'];
      return path is String && path.isNotEmpty
          ? ChatWallpaper.image(path)
          : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper &&
      other.kind == kind &&
      other.presetId == presetId &&
      other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(kind, presetId, imagePath);
}

@immutable
class ChatWallpaperPreset {
  const ChatWallpaperPreset({
    required this.id,
    required this.colors,
    this.patternColor = const Color(0x18FFFFFF),
  });

  final String id;
  final List<Color> colors;
  final Color patternColor;
}

const chatWallpaperPresets = <ChatWallpaperPreset>[
  ChatWallpaperPreset(
    id: 'sky',
    colors: [Color(0xFF91C8EA), Color(0xFFB8E0D2), Color(0xFFF2D6A2)],
  ),
  ChatWallpaperPreset(
    id: 'aurora',
    colors: [Color(0xFF354A78), Color(0xFF786FA6), Color(0xFFE0A2B4)],
  ),
  ChatWallpaperPreset(
    id: 'mint',
    colors: [Color(0xFF80C9B8), Color(0xFFC7DFB7), Color(0xFFF5E8B7)],
    patternColor: Color(0x220F6657),
  ),
  ChatWallpaperPreset(
    id: 'sunset',
    colors: [Color(0xFFF4A58A), Color(0xFFE98DA6), Color(0xFF9A7FC2)],
  ),
  ChatWallpaperPreset(
    id: 'ocean',
    colors: [Color(0xFF176B87), Color(0xFF64CCC5), Color(0xFFDAFFFB)],
    patternColor: Color(0x24204655),
  ),
  ChatWallpaperPreset(
    id: 'night',
    colors: [Color(0xFF111827), Color(0xFF27365C), Color(0xFF634B7A)],
  ),
];

ChatWallpaperPreset? chatWallpaperPreset(String id) {
  for (final preset in chatWallpaperPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

class ChatWallpaperController extends ChangeNotifier {
  ChatWallpaperController({
    Future<SharedPreferences> Function()? preferences,
    Future<Directory> Function()? supportDirectory,
    int Function()? activeSlot,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _activeSlot = activeSlot ?? (() => TdClient.shared.activeSlot);

  static final shared = ChatWallpaperController();

  final Future<SharedPreferences> Function() _preferences;
  final Future<Directory> Function() _supportDirectory;
  final int Function() _activeSlot;
  final Map<String, ChatWallpaper?> _values = {};
  final Set<String> _loaded = {};

  String _id(int chatId) => '${_activeSlot()}:$chatId';
  String _preferenceKey(int chatId) => 'mithka.chatWallpaper.v1.${_id(chatId)}';

  ChatWallpaper? wallpaperFor(int chatId) => _values[_id(chatId)];

  Future<void> load(int chatId) async {
    final id = _id(chatId);
    if (_loaded.contains(id)) return;
    _loaded.add(id);
    try {
      final encoded = (await _preferences()).getString(_preferenceKey(chatId));
      final value = encoded == null
          ? null
          : ChatWallpaper.fromJson(jsonDecode(encoded));
      if (value?.kind == ChatWallpaperKind.image &&
          !File(value!.imagePath!).existsSync()) {
        _values[id] = null;
      } else {
        _values[id] = value;
      }
    } catch (_) {
      _values[id] = null;
    }
    notifyListeners();
  }

  Future<void> setPreset(int chatId, String presetId) async {
    if (chatWallpaperPreset(presetId) == null) return;
    await _replace(chatId, ChatWallpaper.preset(presetId));
  }

  Future<void> setImage(int chatId, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final current = wallpaperFor(chatId);
    if (current?.kind == ChatWallpaperKind.image &&
        current?.imagePath == sourcePath) {
      return;
    }
    final support = await _supportDirectory();
    final folder = Directory(
      '${support.path}/chat_wallpapers/${_activeSlot()}',
    );
    await folder.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final rawExtension = dot >= 0
        ? sourcePath.substring(dot).toLowerCase()
        : '';
    final extension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(rawExtension)
        ? rawExtension
        : '.jpg';
    final destination = File('${folder.path}/$chatId$extension');
    final old = current;
    if (await destination.exists()) await destination.delete();
    await source.copy(destination.path);
    if (old?.kind == ChatWallpaperKind.image &&
        old!.imagePath != destination.path) {
      await _deleteImage(old.imagePath);
    }
    await _store(chatId, ChatWallpaper.image(destination.path));
  }

  Future<void> clear(int chatId) async {
    final old = wallpaperFor(chatId);
    if (old?.kind == ChatWallpaperKind.image) {
      await _deleteImage(old!.imagePath);
    }
    final id = _id(chatId);
    _loaded.add(id);
    _values[id] = null;
    await (await _preferences()).remove(_preferenceKey(chatId));
    notifyListeners();
  }

  Future<void> _replace(int chatId, ChatWallpaper wallpaper) async {
    final old = wallpaperFor(chatId);
    if (old?.kind == ChatWallpaperKind.image) {
      await _deleteImage(old!.imagePath);
    }
    await _store(chatId, wallpaper);
  }

  Future<void> _store(int chatId, ChatWallpaper wallpaper) async {
    final id = _id(chatId);
    _loaded.add(id);
    _values[id] = wallpaper;
    await (await _preferences()).setString(
      _preferenceKey(chatId),
      jsonEncode(wallpaper.toJson()),
    );
    notifyListeners();
  }

  Future<void> _deleteImage(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    super.key,
    required this.wallpaper,
    required this.fallbackColor,
    this.child,
    this.imageScrim = const Color(0x12000000),
  });

  final ChatWallpaper? wallpaper;
  final Color fallbackColor;
  final Widget? child;
  final Color imageScrim;

  @override
  Widget build(BuildContext context) {
    final value = wallpaper;
    if (value == null) return ColoredBox(color: fallbackColor, child: child);
    if (value.kind == ChatWallpaperKind.image) {
      final path = value.imagePath;
      if (path == null || !File(path).existsSync()) {
        return ColoredBox(color: fallbackColor, child: child);
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true),
          ColoredBox(color: imageScrim),
          ?child,
        ],
      );
    }
    final preset = chatWallpaperPreset(value.presetId ?? '');
    if (preset == null) return ColoredBox(color: fallbackColor, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors,
        ),
      ),
      child: CustomPaint(
        painter: _WallpaperPatternPainter(preset.patternColor),
        child: child,
      ),
    );
  }
}

class _WallpaperPatternPainter extends CustomPainter {
  const _WallpaperPatternPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const tile = 86.0;
    for (var row = -1; row <= (size.height / tile).ceil(); row++) {
      for (var column = -1; column <= (size.width / tile).ceil(); column++) {
        final x = column * tile + (row.isOdd ? tile / 2 : 0);
        final y = row * tile;
        final center = Offset(x + 25, y + 26);
        canvas.drawCircle(center, 8, paint);
        canvas.drawLine(
          center + const Offset(-13, 18),
          center + const Offset(13, 18),
          paint,
        );
        final path = Path()
          ..moveTo(x + 53, y + 52)
          ..quadraticBezierTo(x + 66, y + 39, x + 75, y + 56)
          ..quadraticBezierTo(x + 65, y + 68, x + 53, y + 52);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}
