import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/mini_now_playing.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/component/side_nav.dart';
import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigation,
    this.nowPlaying = const MiniNowPlaying(),
  });

  final StatefulNavigationShell navigation;
  final Widget nowPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void select(int index) {
      final path = destinations[index].desPath;
      if (app_paths.START_PAGES.contains(path)) {
        AppPreference.instance.startPage = path;
      }
      if (index != navigation.currentIndex) navigation.goBranch(index);
      if (path == app_paths.SEARCH_PAGE) searchFocusRequest.value++;
    }

    void openSearch() => select(destinations.indexWhere(
        (destination) => destination.desPath == app_paths.SEARCH_PAGE));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            openSearch,
      },
      child: Focus(
        autofocus: true,
        child: ResponsiveBuilder(builder: (context, screenType) {
          final small = screenType == ScreenType.small;
          final nav =
              SideNav(selected: navigation.currentIndex, onSelected: select);
          return Scaffold(
            backgroundColor: scheme.surfaceContainer,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: TitleBar(onSearch: openSearch),
            ),
            drawer: small ? nav : null,
            body: Row(children: [
              if (!small) nav,
              Expanded(
                child: Stack(children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.only(topLeft: Radius.circular(8)),
                    child: navigation,
                  ),
                  nowPlaying,
                ]),
              ),
            ]),
          );
        }),
      ),
    );
  }
}
