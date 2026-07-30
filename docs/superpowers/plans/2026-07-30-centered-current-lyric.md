# Centered Current Lyric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the complete current lyric tile vertically centered in the lyric viewport across playback, seeking, font changes, wrapping, resizing, and responsive layout changes.

**Architecture:** Extract the centering primitive into a small testable helper around `Scrollable.ensureVisible(alignment: 0.5)`. The existing vertical lyric state calls one scheduling method from every positioning trigger and listens only to viewport-size and lyric-view-controller changes; manual scrolling remains untouched until the next lyric transition.

**Tech Stack:** Flutter/Dart, `Scrollable.ensureVisible`, `LayoutBuilder`, Provider, `flutter_test`.

## Global Constraints

- Apply the same centering rule to wide and narrow now-playing layouts.
- Center the complete lyric tile, including translation and wrapped lines, inside the lyric viewport above the playback controls.
- Preserve the existing 300 ms duration and `Curves.fastOutSlowIn` animation.
- Do not modify lyric parsing, playback position logic, BASS, WASAPI, or `desktop_lyric`.
- Manual scrolling must not immediately snap back; the next valid lyric transition restores centering.
- Add no new package dependency.

## File Map

- Create `lib/page/now_playing_page/component/lyric_scroll_positioner.dart`: one testable centering primitive.
- Modify `lib/page/now_playing_page/component/vertical_lyric_view.dart`: route every positioning trigger through one scheduler.
- Create `test/page/now_playing_page/lyric_scroll_positioner_test.dart`.

---

### Task 1: Testable full-tile centering primitive

**Files:**
- Create: `lib/page/now_playing_page/component/lyric_scroll_positioner.dart`
- Test: `test/page/now_playing_page/lyric_scroll_positioner_test.dart`

**Interfaces:**
- Consumes: a mounted target tile `GlobalKey`.
- Produces: `LyricScrollPositioner.center(GlobalKey, {bool animate = true})`.

- [ ] **Step 1: Write failing centering tests for short and tall targets**

```dart
import 'package:coriander_player/page/now_playing_page/component/lyric_scroll_positioner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpHarness(
  WidgetTester tester,
  GlobalKey targetKey, {
  required double targetHeight,
  double viewportHeight = 300,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: viewportHeight,
        child: ListView(
          children: [
            const SizedBox(height: 400),
            SizedBox(key: targetKey, height: targetHeight),
            const SizedBox(height: 400),
          ],
        ),
      ),
    ),
  ));
}

void main() {
  for (final height in [40.0, 120.0]) {
    testWidgets('centers the complete $height pixel tile', (tester) async {
      final key = GlobalKey();
      await pumpHarness(tester, key, targetHeight: height);
      await LyricScrollPositioner.center(key, animate: false);
      await tester.pump();

      final viewport = tester.getRect(find.byType(Scrollable).first);
      final target = tester.getRect(find.byKey(key));
      expect((target.center.dy - viewport.center.dy).abs(), lessThan(1.0));
    });
  }

  testWidgets('missing or unmounted target is a safe no-op', (tester) async {
    final key = GlobalKey();
    await pumpHarness(tester, GlobalKey(), targetHeight: 40);
    await expectLater(LyricScrollPositioner.center(key), completes);
  });
}
```

- [ ] **Step 2: Run tests and verify the missing-helper failure**

Run: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected: FAIL because `lyric_scroll_positioner.dart` does not exist.

- [ ] **Step 3: Implement the centering primitive**

```dart
import 'package:flutter/material.dart';

abstract final class LyricScrollPositioner {
  static const duration = Duration(milliseconds: 300);
  static const curve = Curves.fastOutSlowIn;

  static Future<void> center(
    GlobalKey targetKey, {
    bool animate = true,
  }) async {
    final targetContext = targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: animate ? duration : Duration.zero,
      curve: curve,
    );
  }
}
```

- [ ] **Step 4: Run centering tests**

Run: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected: PASS for both short and tall targets.

- [ ] **Step 5: Commit the primitive**

```powershell
git add lib/page/now_playing_page/component/lyric_scroll_positioner.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
git commit -m "test: define current lyric centering"
```

---

### Task 2: Route every lyric positioning trigger through the center scheduler

**Files:**
- Modify: `lib/page/now_playing_page/component/vertical_lyric_view.dart:99-227`
- Modify: `test/page/now_playing_page/lyric_scroll_positioner_test.dart`

**Interfaces:**
- Consumes: `LyricScrollPositioner.center`, `currentLyricTileKey`, `LyricViewController`, and viewport constraints.
- Produces: `_scheduleCurrentLyricCenter({bool animate = true})`, a single positioning path for initialization, line changes, seek taps, font/alignment changes, and viewport resizing.

- [ ] **Step 1: Add a resize regression test to the harness**

Use a `ValueNotifier<double>` for viewport height and a `ValueListenableBuilder`. Center at height 300, change the height to 500, call the same centering helper after the frame, and assert the target center equals the resized viewport center. This test proves the helper can be reused after responsive changes without hard-coded offsets.

- [ ] **Step 2: Run the helper tests before integration**

Run: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected: PASS; this establishes the integration target.

- [ ] **Step 3: Replace both hard-coded `alignment: 0.25` blocks**

Import `lyric_scroll_positioner.dart` and add:

```dart
bool _centerScheduled = false;

void _scheduleCurrentLyricCenter({bool animate = true}) {
  if (_centerScheduled || !mounted) return;
  _centerScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    _centerScheduled = false;
    if (!mounted) return;
    await LyricScrollPositioner.center(
      currentLyricTileKey,
      animate: animate,
    );
  });
}
```

Call it after `_generateLyricTiles` during `_initLyricView`, `_updateNextLyricLine`, and `_seekToLyricLine`. Remove duplicated `Scrollable.ensureVisible` code entirely.

- [ ] **Step 4: Recenter after font/alignment changes without reacting to manual scroll**

Attach to the provided `LyricViewController` in `didChangeDependencies`:

```dart
LyricViewController? _lyricViewController;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final next = context.read<LyricViewController>();
  if (identical(next, _lyricViewController)) return;
  _lyricViewController?.removeListener(_scheduleCurrentLyricCenter);
  _lyricViewController = next;
  _lyricViewController!.addListener(_scheduleCurrentLyricCenter);
}
```

Remove this listener in `dispose`. Do not add a `ScrollController` listener; user scrolling must remain free until the next lyric event.

- [ ] **Step 5: Recenter after viewport-size changes**

Wrap the existing `CustomScrollView` in `LayoutBuilder`, compare `Size(constraints.maxWidth, constraints.maxHeight)` with a stored `_lastViewportSize`, and schedule centering only when the finite size actually changes:

```dart
Size? _lastViewportSize;

Widget _buildScrollView(BoxConstraints constraints) {
  final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
  if (nextSize != _lastViewportSize) {
    _lastViewportSize = nextSize;
    _scheduleCurrentLyricCenter(animate: false);
  }
}
```

Place this size-comparison block at the start of the `LayoutBuilder` callback, then return the existing `CustomScrollView` with its current key, controller, and three slivers unchanged. Use no animation for a live resize to avoid a continuous 300 ms lag. Natural lyric transitions and seeks retain the 300 ms animation.

- [ ] **Step 6: Run tests and static analysis**

Run: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected: PASS.

Run: `flutter analyze lib/page/now_playing_page/component/vertical_lyric_view.dart lib/page/now_playing_page/component/lyric_scroll_positioner.dart`

Expected: no diagnostics.

- [ ] **Step 7: Commit the integration**

```powershell
git add lib/page/now_playing_page/component/vertical_lyric_view.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
git commit -m "fix: center the current lyric tile"
```

---

### Task 3: Responsive and playback regression verification

**Files:**
- Modify only files needed to fix verified failures.

**Interfaces:**
- Consumes: completed centering integration.
- Produces: verified behavior across supported now-playing layouts and triggers.

- [ ] **Step 1: Run focused and full Flutter tests**

Run: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected: PASS.

Run: `flutter test`

Expected: all tests PASS.

- [ ] **Step 2: Run analysis and Windows build**

Run: `flutter analyze`

Expected: no diagnostics.

Run: `flutter build windows --release`

Expected: exit code 0.

- [ ] **Step 3: Perform manual geometric acceptance**

Test widths below and above the existing 928 px responsive breakpoint, short and tall windows, normal LRC, translated lyrics, a line that wraps to at least three visual rows, font-size increase/decrease, alignment switching, progress dragging, lyric-row clicking, and natural line changes. For each case, compare the complete highlighted tile's center with the lyric panel center, excluding the bottom progress/control region. Manually scroll away and verify it stays away until the next lyric transition, then returns to center.

- [ ] **Step 4: Confirm the verification task leaves a clean worktree**

```powershell
git status --short
```

Expected: no output. This verification-only task creates no commit. If manual or automated verification exposes a defect, return to Task 2, add a focused failing regression test, fix it, and amend the Task 2 commit using its explicit file list.
