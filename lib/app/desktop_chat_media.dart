import 'package:flutter/widgets.dart';

import 'desktop_chat_media_stub.dart'
    if (dart.library.io) 'desktop_chat_media_io.dart'
    as implementation;

Widget desktopChatLocalMedia({
  required String path,
  required BorderRadius borderRadius,
}) => implementation.desktopChatLocalMedia(
  path: path,
  borderRadius: borderRadius,
);
