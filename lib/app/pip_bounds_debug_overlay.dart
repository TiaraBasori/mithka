//
//  pip_bounds_debug_overlay.dart
//
//  Pointer-transparent overlay that marks the app-level PiP frame and viewport
//  while diagnosing rotation/split-screen placement bugs.
//

import 'package:flutter/material.dart';

class PiPBoundsDebugOverlay extends StatelessWidget {
  const PiPBoundsDebugOverlay({
    super.key,
    required this.offset,
    required this.size,
    required this.viewport,
  });

  final Offset offset;
  final Size size;
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    final text =
        'PiP ${offset.dx.round()},${offset.dy.round()} '
        '${size.width.round()}x${size.height.round()} / '
        '${viewport.width.round()}x${viewport.height.round()}';
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF375F), width: 2),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xCCFF375F),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
