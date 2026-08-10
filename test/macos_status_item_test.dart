import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS menu-bar and Dock reopen the retained main window', () {
    final delegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final window = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    final reopenHandler = delegate.substring(
      delegate.indexOf('override func applicationShouldHandleReopen('),
      delegate.indexOf('private static func mirrorRightControlFlag'),
    );

    expect(delegate, contains('NSStatusBar.system.statusItem'));
    expect(delegate, contains('image.isTemplate = true'));
    expect(delegate, contains('private static func makeStatusItemImage()'));
    expect(delegate, contains('private var retainedMainWindow'));
    expect(delegate, contains('applicationShouldHandleReopen('));
    expect(reopenHandler, contains('bringMainWindowToFront(using: sender)'));
    expect(reopenHandler, contains('return false'));
    expect(
      reopenHandler,
      isNot(contains('return bringMainWindowToFront(using: sender)')),
    );
    expect(delegate, contains('primaryWindow.makeKeyAndOrderFront(nil)'));
    expect(delegate, contains('application.unhide(nil)'));
    expect(delegate, contains('application.activate(ignoringOtherApps: true)'));
    expect(delegate, contains('action: #selector(quitApplication)'));
    expect(
      delegate,
      contains(
        'applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n    // The menu-bar item remains available',
      ),
    );
    expect(delegate, contains('return false'));
    expect(delegate, isNot(contains('NSImage(systemSymbolName:')));

    expect(window, contains('override func close()'));
    expect(window, contains('override func miniaturize(_ sender: Any?)'));
    expect(window, contains('orderOut(nil)'));
    expect(window, contains('orderOut(sender)'));
    expect(window, contains('isReleasedWhenClosed = false'));

    expect(info, contains('<key>LSMultipleInstancesProhibited</key>'));
    expect(info, contains('<true/>'));
  });
}
