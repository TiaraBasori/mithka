import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS menu-bar item can reopen the retained main window', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('NSStatusBar.system.statusItem'));
    expect(source, contains('image.isTemplate = true'));
    expect(source, contains('private static func makeStatusItemImage()'));
    expect(source, contains(r'where: { $0 is MainFlutterWindow }'));
    expect(source, contains('primaryWindow.makeKeyAndOrderFront(nil)'));
    expect(source, contains('NSApp.activate(ignoringOtherApps: true)'));
    expect(source, contains('action: #selector(quitApplication)'));
    expect(
      source,
      contains(
        'applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n    // The menu-bar item remains available',
      ),
    );
    expect(source, contains('return false'));
    expect(source, isNot(contains('NSImage(systemSymbolName:')));
  });
}
