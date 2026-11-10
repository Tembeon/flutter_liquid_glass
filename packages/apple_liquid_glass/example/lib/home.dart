import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/glass/glass_page.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/search_page.dart';
import 'package:apple_liquid_glass_example/showcase/showcase_page.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The gallery's tabs, each an answer to one question about the package.
enum GalleryTab {
  /// What can it do: whole screens, playing.
  showcase,

  /// What is it made of: the material, a property at a time.
  glass,

  /// What is in it: every widget, with its name.
  components,

  /// How does it move: springs, layouts and morphs.
  motion,
}

/// The gallery: four tabs and a search over all of it.
class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  var _tab = GalleryTab.showcase;
  final _search = GlassSearchController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(GalleryTab tab) {
    _search.closeView();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: const [
        GlassTabDestination(
          icon: Icon(CupertinoIcons.sparkles),
          label: Text('Showcase'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.drop),
          selectedIcon: Icon(CupertinoIcons.drop_fill),
          label: Text('Glass'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.square_grid_2x2),
          selectedIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
          label: Text('Components'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.wind),
          label: Text('Motion'),
        ),
      ],
      selectedIndex: _tab.index,
      onDestinationSelected: (index) =>
          setState(() => _tab = GalleryTab.values[index]),
      searchController: _search,
    ),
    tabBuilder: (context, index) => switch (GalleryTab.values[index]) {
      GalleryTab.showcase => const ShowcasePage(),
      GalleryTab.glass => const GlassPage(),
      GalleryTab.components => const ComponentsPage(),
      GalleryTab.motion => const MotionPage(),
    },
    searchBuilder: (context) =>
        GallerySearchPage(controller: _search, onOpen: _open),
  );
}
