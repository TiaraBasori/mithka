//
//  gif_preview.dart
//
//  Loops a visible saved GIF/MP4 animation and keeps its thumbnail on screen
//  while TDLib downloads or initializes the animation file.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../components/photo_avatar.dart';
import '../tdlib/td_image_loader.dart';
import 'gif_item.dart';

class GifPreview extends StatefulWidget {
  const GifPreview({super.key, required this.item});

  final GifItem item;

  @override
  State<GifPreview> createState() => _GifPreviewState();
}

class _GifPreviewState extends State<GifPreview> {
  VideoPlayerController? _controller;
  int? _loadingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GifPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) _load();
  }

  Future<void> _load() async {
    final id = widget.item.id;
    _loadingId = id;
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose();

    final path = await TdFileCenter.shared.path(id);
    if (!mounted || path == null || _loadingId != id) return;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      return;
    }
    if (!mounted || _loadingId != id) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _loadingId = null;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(
            photo: widget.item.thumbnail ?? widget.item.file,
            cornerRadius: 0,
          ),
          if (controller != null && controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
        ],
      ),
    );
  }
}
