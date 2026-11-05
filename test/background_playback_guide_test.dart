import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/services/reader/background_playback_guide.dart';
import 'package:translation_app/state/settings_controller.dart';

void main() {
  setUp(() {
    BackgroundPlaybackGuide.introShown = false;
    BackgroundPlaybackGuide.failureShown = false;
  });

  test('shows once, again after a failure, and never after dismiss', () {
    expect(
      shouldShowBackgroundGuide(
        dismissedForever: false,
        introShown: false,
        failureShown: false,
        becauseFailed: false,
        becauseInterrupted: false,
      ),
      isTrue,
    );
    expect(
      shouldShowBackgroundGuide(
        dismissedForever: false,
        introShown: true,
        failureShown: false,
        becauseFailed: false,
        becauseInterrupted: false,
      ),
      isFalse,
    );
    expect(
      shouldShowBackgroundGuide(
        dismissedForever: false,
        introShown: true,
        failureShown: false,
        becauseFailed: true,
        becauseInterrupted: false,
      ),
      isTrue,
    );
    expect(
      shouldShowBackgroundGuide(
        dismissedForever: false,
        introShown: false,
        failureShown: false,
        becauseFailed: false,
        becauseInterrupted: true,
      ),
      isTrue,
    );
    expect(
      shouldShowBackgroundGuide(
        dismissedForever: true,
        introShown: false,
        failureShown: false,
        becauseFailed: true,
        becauseInterrupted: true,
      ),
      isFalse,
    );
  });

  testWidgets('不再提示 is remembered and the dialog can be dismissed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  BackgroundPlaybackGuide.maybeShow(
                    context,
                    dismissedForever: settings.backgroundPlaybackGuideDismissed,
                    onDismissForever: settings.dismissBackgroundPlaybackGuide,
                  );
                },
                child: const Text('听书'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('听书'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('让听书在后台继续'), findsOneWidget);
    expect(find.textContaining('电池优化'), findsOneWidget);

    await tester.tap(find.text('不再提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings.backgroundPlaybackGuideDismissed, isTrue);
    expect(find.text('让听书在后台继续'), findsNothing);

    await tester.tap(find.text('听书'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('让听书在后台继续'), findsNothing);
  });
}
