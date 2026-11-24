import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/stand/controls_page.dart';
import 'package:apple_liquid_glass_example/stand/liquid_page.dart';
import 'package:apple_liquid_glass_example/stand/photos_page.dart';
import 'package:apple_liquid_glass_example/stand/present_page.dart';
import 'package:apple_liquid_glass_example/stand/search_page.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum StandTab { liquid, controls, present, motion, photos }

/// The pages the device benches drive (lib/perf/app_bench.dart) and the
/// glass budgets count: five tabs kept as they are, so a number measured
/// on them compares with the one before. The gallery people see is
/// `GalleryHome`.

class StandHome extends StatefulWidget {
  const StandHome({super.key});

  @override
  State<StandHome> createState() => _StandHomeState();
}

class _StandHomeState extends State<StandHome> {
  final _tabs = GlassTabController();
  final _search = GlassSearchController();

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _open(StandTab tab) {
    _search.closeView();
    _tabs.index = tab.index;
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    controller: _tabs,
    searchController: _search,
    tabs: [
      GlassTab(
        icon: const Icon(CupertinoIcons.drop),
        selectedIcon: const Icon(CupertinoIcons.drop_fill),
        label: const Text('Liquid'),
        builder: (context) => const LiquidPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.slider_horizontal_3),
        label: const Text('Controls'),
        builder: (context) => const ControlsPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.square_stack_3d_up),
        selectedIcon: const Icon(CupertinoIcons.square_stack_3d_up_fill),
        label: const Text('Present'),
        builder: (context) => const PresentPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.wind),
        label: const Text('Motion'),
        builder: (context) => const MotionPage(),
      ),
      GlassTab(
        icon: const Icon(CupertinoIcons.photo_on_rectangle),
        selectedIcon: const Icon(CupertinoIcons.photo_fill_on_rectangle_fill),
        label: const Text('Photos'),
        badge: const GlassBadge.count(6),
        builder: (context) => const PhotosPage(),
      ),
    ],
    searchBuilder: (context) => SearchPage(controller: _search, onOpen: _open),
  );
}
