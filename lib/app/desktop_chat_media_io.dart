import 'dart:io';

import 'package:flutter/widgets.dart';

Widget desktopChatLocalMedia({
  required String path,
  required BorderRadius borderRadius,
}) => ClipRRect(
  borderRadius: borderRadius,
  child: Image.file(
    File(path),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  ),
);
