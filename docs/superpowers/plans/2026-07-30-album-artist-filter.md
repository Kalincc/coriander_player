# Album Artist Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a searchable single-artist filter to the album page while preserving existing album sorting and list/table behavior.

**Architecture:** Add one album-specific filter button/dialog whose public value is a nullable artist name (`null` means “无分类”). Convert `AlbumsPage` to local state, derive a fresh album list from the current `AudioLibrary`, and pass it to the existing `UniPage`; a value key resets stale scroll position when the filter changes. Extend `UniPage` only with an optional empty-state widget.

**Tech Stack:** Flutter/Dart Material widgets, existing `AudioLibrary`, `UniPage`, pinyin-aware `localeCompareTo`, `flutter_test`.

## Global Constraints

- Place the artist filter in the album page top toolbar beside the current sort controls.
- The first choice is “无分类” and displays all albums.
- Select at most one artist and provide a name-search field inside the selector.
- Existing title/work-count sorting, ascending/descending order, and list/table view operate on the filtered list.
- Do not persist the artist selection to `app_preference.json`; every application start defaults to “无分类”.
- Do not refactor unrelated navigation or generalize the filter beyond the album page.
- Add no new package dependency.

## File Map

- Create `lib/page/album_artist_filter.dart`: pure album derivation plus the filter button and searchable dialog.
- Modify `lib/page/albums_page.dart`: local selected-artist state and filtered `UniPage` input.
- Modify `lib/page/uni_page.dart`: optional explicit empty-state body.
- Create `test/page/album_artist_filter_test.dart`.
- Create `test/page/uni_page_empty_state_test.dart`.

---

### Task 1: Searchable artist selection component

**Files:**
- Create: `lib/page/album_artist_filter.dart`
- Test: `test/page/album_artist_filter_test.dart`

**Interfaces:**
- Consumes: artist names and an optional selected artist name.
- Produces: `filterArtistNames`, `albumsForArtist`, and `AlbumArtistFilterButton(artistNames:, selectedArtistName:, onSelected:)`.

- [ ] **Step 1: Write failing pure-function and widget tests**

```dart
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_artist_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artist names are pinyin-sorted and filtered case-insensitively', () {
    expect(filterArtistNames(['周杰伦', 'Aimer', '陈奕迅'], 'ai'), ['Aimer']);
    expect(filterArtistNames(['周杰伦', 'Aimer', '陈奕迅'], ''),
        ['Aimer', '陈奕迅', '周杰伦']);
  });

  test('null artist returns all albums and a named artist returns its albums', () {
    final all = [Album(name: 'All 1'), Album(name: 'All 2')];
    final artist = Artist(name: 'Artist')..albumsMap['Only'] = Album(name: 'Only');
    expect(albumsForArtist(allAlbums: all, artists: {'Artist': artist}, artistName: null), all);
    expect(
      albumsForArtist(allAlbums: all, artists: {'Artist': artist}, artistName: 'Artist')
          .map((album) => album.name),
      ['Only'],
    );
    expect(albumsForArtist(allAlbums: all, artists: {}, artistName: 'Removed'), all);
  });

  testWidgets('dialog searches, selects an artist, and can reset to no category',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        return AlbumArtistFilterButton(
          artistNames: const ['Aimer', '陈奕迅', '周杰伦'],
          selectedArtistName: selected,
          onSelected: (value) => setState(() => selected = value),
        );
      }),
    ));

    await tester.tap(find.text('艺术家：无分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '周');
    await tester.pump();
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('陈奕迅'), findsNothing);
    await tester.tap(find.text('周杰伦'));
    await tester.pumpAndSettle();
    expect(find.text('艺术家：周杰伦'), findsOneWidget);

    await tester.tap(find.text('艺术家：周杰伦'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无分类'));
    await tester.pumpAndSettle();
    expect(find.text('艺术家：无分类'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests and verify the missing-component failure**

Run: `flutter test test/page/album_artist_filter_test.dart`

Expected: FAIL because `album_artist_filter.dart` does not exist.

- [ ] **Step 3: Implement pure derivation functions**

```dart
List<String> filterArtistNames(Iterable<String> names, String query) {
  final normalized = query.trim().toLowerCase();
  final result = names
      .where((name) => name.toLowerCase().contains(normalized))
      .toList(growable: false);
  result.sort((a, b) => a.localeCompareTo(b));
  return result;
}

List<Album> albumsForArtist({
  required Iterable<Album> allAlbums,
  required Map<String, Artist> artists,
  required String? artistName,
}) {
  final artist = artistName == null ? null : artists[artistName];
  return artist == null
      ? List<Album>.from(allAlbums)
      : List<Album>.from(artist.albumsMap.values);
}
```

The missing-artist fallback deliberately returns all albums, satisfying the music-library-refresh rule.

- [ ] **Step 4: Implement the button and stateful searchable dialog**

Use this public API:

```dart
class AlbumArtistFilterButton extends StatelessWidget {
  final List<String> artistNames;
  final String? selectedArtistName;
  final ValueChanged<String?> onSelected;
  const AlbumArtistFilterButton({
    super.key,
    required this.artistNames,
    required this.selectedArtistName,
    required this.onSelected,
  });
}
```

Render a 40 px tonal button labelled `艺术家：${selectedArtistName ?? '无分类'}`. On tap, show a dialog containing one `TextField`, a fixed “无分类” row, and a bounded `ListView` of `filterArtistNames`. Dialog selection invokes `onSelected(null)` for “无分类” or `onSelected(name)` for an artist, then closes. Closing the dialog through Escape or the close affordance must not call the callback.

- [ ] **Step 5: Run component tests**

Run: `flutter test test/page/album_artist_filter_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the filter component**

```powershell
git add lib/page/album_artist_filter.dart test/page/album_artist_filter_test.dart
git commit -m "feat: add searchable album artist filter"
```

---

### Task 2: Explicit empty state support in `UniPage`

**Files:**
- Modify: `lib/page/uni_page.dart:97-136,243-283`
- Test: `test/page/uni_page_empty_state_test.dart`

**Interfaces:**
- Consumes: existing `UniPage<T>` callers unchanged.
- Produces: optional `Widget? emptyState`; when `contentList.isEmpty`, it replaces the list/grid body.

- [ ] **Step 1: Write the failing empty-state widget test**

Pump `UniPage<String>` with an empty list, all action flags false, a normal `PagePreference`, and `emptyState: const Center(child: Text('没有专辑'))`. Assert `没有专辑` appears and no `ListView`/`GridView` is built. Pump a second case with one item and assert the item appears instead of the empty state.

- [ ] **Step 2: Run the test and verify the missing-parameter failure**

Run: `flutter test test/page/uni_page_empty_state_test.dart`

Expected: FAIL because `UniPage` has no `emptyState` parameter.

- [ ] **Step 3: Add the backward-compatible optional body**

Add `this.emptyState` immediately after `this.multiSelectViewActions` in the existing constructor and add this field immediately after `multiSelectViewActions`:

```dart
final Widget? emptyState;
```

In `result`, choose the body before the existing list/table switch:

```dart
body: widget.contentList.isEmpty && widget.emptyState != null
    ? widget.emptyState!
    : Material(
        type: MaterialType.transparency,
        child: switch (currContentView) {
          ContentView.list => ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 96.0),
              itemCount: widget.contentList.length,
              itemExtent: 64,
              itemBuilder: (context, i) => widget.contentBuilder(
                context, widget.contentList[i], i, multiSelectController,
              ),
            ),
          ContentView.table => GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 96.0),
              gridDelegate: gridDelegate,
              itemCount: widget.contentList.length,
              itemBuilder: (context, i) => widget.contentBuilder(
                context, widget.contentList[i], i, multiSelectController,
              ),
            ),
        },
      ),
```

- [ ] **Step 4: Run the focused test and existing test suite**

Run: `flutter test test/page/uni_page_empty_state_test.dart`

Expected: PASS.

Run: `flutter test`

Expected: all tests PASS.

- [ ] **Step 5: Commit the reusable empty state**

```powershell
git add lib/page/uni_page.dart test/page/uni_page_empty_state_test.dart
git commit -m "feat: support empty content in unified pages"
```

---

### Task 3: Integrate artist filtering into the album page

**Files:**
- Modify: `lib/page/albums_page.dart:1-58`
- Modify: `test/page/album_artist_filter_test.dart`

**Interfaces:**
- Consumes: `AlbumArtistFilterButton`, `albumsForArtist`, `AudioLibrary.artistCollection`, `AudioLibrary.albumCollection`, and existing album sort descriptors.
- Produces: a stateful `AlbumsPage` whose local `_selectedArtistName` is never serialized.

- [ ] **Step 1: Add an integration-oriented state test**

Extend `album_artist_filter_test.dart` with a harness that owns `selectedArtistName`, derives albums through `albumsForArtist`, sorts the derived list with the same title comparator used by `AlbumsPage`, and asserts: all albums appear for null; only the chosen artist's albums appear after selection; ascending/descending sorting is applied to the filtered list; a removed artist name falls back to all albums. Also assert `AppPreference.instance.albumsPagePref.toMap()` has exactly `sortMethod`, `sortOrder`, and `contentView`, with no artist field.

- [ ] **Step 2: Run the test before page integration**

Run: `flutter test test/page/album_artist_filter_test.dart`

Expected: PASS, defining the state behavior the page must wire.

- [ ] **Step 3: Convert `AlbumsPage` to state and derive the filtered list**

```dart
class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});
  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  String? _selectedArtistName;

  @override
  Widget build(BuildContext context) {
    final library = AudioLibrary.instance;
    final selectedExists = _selectedArtistName == null ||
        library.artistCollection.containsKey(_selectedArtistName);
    final effectiveArtistName = selectedExists ? _selectedArtistName : null;
    final contentList = albumsForArtist(
      allAlbums: library.albumCollection.values,
      artists: library.artistCollection,
      artistName: effectiveArtistName,
    );
    final artistNames = filterArtistNames(
      library.artistCollection.keys,
      '',
    );
  }
}
```

After these derived variables, return the existing `UniPage<Album>` construction. Keep its `contentBuilder`, all four enable flags, and both existing `SortMethodDesc<Album>` definitions unchanged; Step 4 gives every changed argument explicitly.

Do not write `_selectedArtistName` to `AppPreference` or `AppSettings`.

- [ ] **Step 4: Add the toolbar filter, subtitle, key, and empty state**

Pass these additions to the existing `UniPage<Album>` while retaining both existing sort methods unchanged:

```dart
key: ValueKey(effectiveArtistName ?? '__all_albums__'),
subtitle: effectiveArtistName == null
    ? '${contentList.length} 张专辑'
    : '该艺术家的 ${contentList.length} 张专辑',
primaryAction: AlbumArtistFilterButton(
  artistNames: artistNames,
  selectedArtistName: effectiveArtistName,
  onSelected: (name) => setState(() => _selectedArtistName = name),
),
emptyState: const Center(child: Text('该艺术家没有专辑')),
```

The value key recreates only `UniPage` when the filter changes, resets an out-of-range scroll position, and reloads the current sort/view choices from `albumsPagePref`.

- [ ] **Step 5: Run focused tests and analysis**

Run: `flutter test test/page/album_artist_filter_test.dart test/page/uni_page_empty_state_test.dart`

Expected: PASS.

Run: `flutter analyze lib/page/albums_page.dart lib/page/album_artist_filter.dart lib/page/uni_page.dart`

Expected: no diagnostics.

- [ ] **Step 6: Commit album-page integration**

```powershell
git add lib/page/albums_page.dart test/page/album_artist_filter_test.dart
git commit -m "feat: filter albums by artist"
```

---

### Task 4: Album filter responsive and regression verification

**Files:**
- Modify only files needed to fix verified failures.

**Interfaces:**
- Consumes: completed album artist filter.
- Produces: verified filtering that preserves all pre-existing album page controls.

- [ ] **Step 1: Run focused and full tests**

Run: `flutter test test/page/album_artist_filter_test.dart test/page/uni_page_empty_state_test.dart`

Expected: PASS.

Run: `flutter test`

Expected: all tests PASS.

- [ ] **Step 2: Run analysis and Windows build**

Run: `flutter analyze`

Expected: no diagnostics.

Run: `flutter build windows --release`

Expected: exit code 0.

- [ ] **Step 3: Perform manual acceptance**

Verify the filter button is visible beside the existing album controls at large width and remains the first visible action in the existing small-screen folded layout. Search Chinese and Latin artist names, select an artist with several albums, switch title/work-count sort and ascending/descending order, switch list/table view, return to “无分类”, navigate away/back, and restart the player. Confirm restart always shows all albums and no artist filter field appears in `app_preference.json`.

- [ ] **Step 4: Confirm the verification task leaves a clean worktree**

```powershell
git status --short
```

Expected: no output. This verification-only task creates no commit. If verification exposes a defect, return to the owning task, add a focused failing test, apply the fix, and amend that task's commit using its explicit file list.
