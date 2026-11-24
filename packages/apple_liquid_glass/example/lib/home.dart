import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/glass/glass_page.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/search_page.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The gallery's tabs.
enum GalleryTab {
  /// Every component, live, with its parameters to try.
  components,

  /// The material, a property at a time.
  glass,

  /// Springs, layouts that animate and morphs.
  motion,
}

/// The gallery: a catalog of components first, the material and the motion
/// beside it, and a search over all of it.
class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  final _tabs = GlassTabController();
  final _search = GlassSearchController();

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _open(GalleryTab tab) {
    _search.closeView();
    _tabs.index = tab.index;
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    controller: _tabs,
    searchController: _search,
    tabs: [
      GlassTab(
        icon: const Icon(CupertinoIcons.square_grid_2x2),
        selectedIcon: const Icon(CupertinoIcons.square_grid_2x2_fill),
        label: const Text('Components'),
        builder: (context) => const ComponentsPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.drop),
        selectedIcon: const Icon(CupertinoIcons.drop_fill),
        label: const Text('Glass'),
        builder: (context) => const GlassPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.wind),
        label: const Text('Motion'),
        builder: (context) => const MotionPage(),
      ),
    ],
    searchBuilder: (context) =>
        GallerySearchPage(controller: _search, onOpen: _open),
  );
}
