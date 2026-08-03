//
//  content_view.dart
//
//  Auth gate: shows the tab bar once TDLib reports ready, otherwise login.
//  Port of the Swift `ContentView` / `SplashView`.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../auth/login_view.dart';
import '../components/app_interactive_surface.dart';
import '../components/drawer_controller.dart' as dc;
import '../platform/adaptive_platform.dart';
import '../theme/app_theme.dart';
import 'desktop_window_controls.dart';
import 'macos_desktop_title_bar.dart';
import 'main_tab_view.dart';

class ContentView extends StatelessWidget {
  const ContentView({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<AuthManager>().step;
    final Widget child = switch (step) {
      AuthReady() => const MainTabView(),
      AuthInitializing() || AuthLoggingOut() => const SplashView(),
      _ => const LoginView(),
    };
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
    if (kIsWeb || !isDesktopTargetPlatform(defaultTargetPlatform)) {
      return content;
    }
    return _DesktopPrimaryWindowFrame(
      accountReady: step is AuthReady,
      child: content,
    );
  }
}

class _DesktopPrimaryWindowFrame extends StatelessWidget {
  const _DesktopPrimaryWindowFrame({
    required this.accountReady,
    required this.child,
  });

  final bool accountReady;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountStore>();
    final activeAccount = accounts.summaries
        .where((account) => account.slot == accounts.activeSlot)
        .firstOrNull;
    final identity = activeAccount?.name.trim();
    final label = identity == null || identity.isEmpty ? 'Mithka' : identity;
    final flutterWindowControls = usesFlutterDesktopWindowControls;
    return ColoredBox(
      color: context.colors.background,
      child: Column(
        children: [
          MacosDesktopTitleBar(
            leadingClearance: defaultTargetPlatform == TargetPlatform.macOS
                ? 78
                : 8,
            trailingControls: flutterWindowControls
                ? const DesktopWindowControls()
                : null,
            onDragAreaDoubleTap: flutterWindowControls
                ? () => unawaited(togglePrimaryDesktopWindowMaximized())
                : null,
            appIdentity: AppInteractiveSurface(
              key: const ValueKey('macos-title-bar-account'),
              semanticLabel: label,
              enabled: accountReady,
              onTap: accountReady
                  ? () => context.read<dc.DrawerController>().open()
                  : null,
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      key: const ValueKey('macos-title-bar-account-avatar'),
                      child: _MacosTitleBarAvatar(
                        path: activeAccount?.avatarPath,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacosTitleBarAvatar extends StatelessWidget {
  const _MacosTitleBarAvatar({this.path});

  final String? path;

  Widget _fallback() => Image.asset(
    'assets/app_icon.png',
    width: 24,
    height: 24,
    fit: BoxFit.cover,
  );

  @override
  Widget build(BuildContext context) {
    final path = this.path?.trim();
    if (path == null || path.isEmpty) return _fallback();
    return Image.file(
      File(path),
      key: const ValueKey('macos-title-bar-account-avatar-file'),
      width: 24,
      height: 24,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/penguin.png'),
              width: AppMetric.splashPenguinSize,
              height: AppMetric.splashPenguinSize,
            ),
            SizedBox(height: AppSpacing.lg + AppSpacing.sm),
            SizedBox(
              width: AppMetric.splashSpinnerSize,
              height: AppMetric.splashSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
