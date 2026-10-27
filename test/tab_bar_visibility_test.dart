import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/drawer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh and repeated root depths do not notify', () {
    final visibility = TabBarVisibility();
    addTearDown(visibility.dispose);
    var notifications = 0;
    visibility.addListener(() => notifications++);

    expect(visibility.depth(0), 0);
    visibility.setDepth(0, 0);
    visibility.setDepth(0, 0);
    visibility.setDepth(1, 0);

    expect(visibility.depth(0), 0);
    expect(visibility.depth(1), 0);
    expect(notifications, 0);
  });

  test('real depth changes notify but equal nonzero depths do not', () {
    final visibility = TabBarVisibility();
    addTearDown(visibility.dispose);
    final depths = <int>[];
    visibility.addListener(() => depths.add(visibility.depth(0)));

    visibility.setDepth(0, 1);
    expect(visibility.depth(0), 1);
    expect(depths, [1]);

    visibility.setDepth(0, 1);
    expect(depths, [1]);

    visibility.setDepth(0, 0);
    expect(visibility.depth(0), 0);
    expect(depths, [1, 0]);

    visibility.setDepth(0, 0);
    expect(depths, [1, 0]);
  });

  testWidgets('idle root attachment is silent; push and pop update the bar', (
    tester,
  ) async {
    final binding = tester.binding;
    final visibility = TabBarVisibility();
    addTearDown(visibility.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final depths = <int>[];
    final initialRoutePhases = <SchedulerPhase>[];
    visibility.addListener(() => depths.add(visibility.depth(0)));
    const barKey = ValueKey('tab-bar');
    const rootKey = ValueKey('root-page');
    const pushedKey = ValueKey('pushed-page');
    final harness = Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedBuilder(
        animation: visibility,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: _TabNavigatorHarness(
                navigatorKey: navigatorKey,
                visibility: visibility,
                rootKey: rootKey,
                onGenerateRoute: () =>
                    initialRoutePhases.add(binding.schedulerPhase),
              ),
            ),
            if (visibility.depth(0) == 0)
              const SizedBox(key: barKey, height: 40),
          ],
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(binding.schedulerPhase, SchedulerPhase.idle);
    binding.attachRootWidget(binding.wrapWithDefaultView(harness));
    // The blank pump leaves an existing RootElement, so attachment marks it
    // dirty rather than mounting immediately. Inflate it while still idle,
    // matching a cold runApp attachment, not pumpWidget's frame-time build.
    binding.buildOwner!.buildScope(binding.rootElement!);
    expect(binding.schedulerPhase, SchedulerPhase.idle);
    expect(initialRoutePhases, [SchedulerPhase.idle]);
    expect(tester.takeException(), isNull);
    expect(depths, isEmpty);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(depths, isEmpty);
    expect(visibility.depth(0), 0);
    expect(find.byKey(rootKey), findsOneWidget);
    expect(find.byKey(barKey), findsOneWidget);

    unawaited(navigatorKey.currentState!.push<void>(_pageRoute(pushedKey)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(visibility.depth(0), 1);
    expect(depths, [1]);
    expect(find.byKey(pushedKey), findsOneWidget);
    expect(find.byKey(barKey), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(visibility.depth(0), 0);
    expect(depths, [1, 0]);
    expect(find.byKey(rootKey), findsOneWidget);
    expect(find.byKey(barKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

PageRoute<void> _pageRoute(Key key) => PageRouteBuilder<void>(
  pageBuilder: (context, animation, secondaryAnimation) => SizedBox(key: key),
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

class _TabNavigatorHarness extends StatefulWidget {
  const _TabNavigatorHarness({
    required this.navigatorKey,
    required this.visibility,
    required this.rootKey,
    required this.onGenerateRoute,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final TabBarVisibility visibility;
  final Key rootKey;
  final VoidCallback onGenerateRoute;

  @override
  State<_TabNavigatorHarness> createState() => _TabNavigatorHarnessState();
}

class _TabNavigatorHarnessState extends State<_TabNavigatorHarness> {
  late final _observer = TabDepthObserver(0, widget.visibility);

  @override
  Widget build(BuildContext context) => Navigator(
    key: widget.navigatorKey,
    observers: [_observer],
    onGenerateRoute: (_) {
      widget.onGenerateRoute();
      return _pageRoute(widget.rootKey);
    },
  );
}
