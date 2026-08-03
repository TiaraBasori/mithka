import 'package:flutter/widgets.dart';

import 'desktop_chat_window_models.dart';

bool get supportsDesktopChatWindows => false;

void attachDesktopChatMainProxy() {}

void detachDesktopChatMainProxy() {}

Future<bool> openDesktopChatWindow(
  DesktopChatWindowArguments arguments,
) async => false;

Future<void> closeCurrentDesktopChatWindow() async {}

DesktopChatWindowChildController createDesktopChatWindowChildController(
  DesktopChatWindowArguments arguments,
) => _UnsupportedDesktopChatWindowChildController();

Widget buildDesktopChatWindowHost({
  required DesktopChatWindowArguments initialArguments,
  required Widget Function(
    BuildContext context,
    DesktopChatWindowArguments arguments,
  )
  builder,
}) => Builder(builder: (context) => builder(context, initialArguments));

class _UnsupportedDesktopChatWindowChildController
    extends DesktopChatWindowChildController {
  @override
  bool get loading => false;

  @override
  bool get sendFailed => true;

  @override
  bool get sending => false;

  @override
  DesktopChatWindowSnapshot? get snapshot => null;

  @override
  Future<bool> sendText(String text) async => false;
}
