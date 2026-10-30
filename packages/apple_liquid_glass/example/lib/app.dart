import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/pages/controls_page.dart';
import 'package:apple_liquid_glass_example/pages/liquid_page.dart';
import 'package:apple_liquid_glass_example/pages/photos_page.dart';
import 'package:apple_liquid_glass_example/pages/present_page.dart';
import 'package:apple_liquid_glass_example/pages/search_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({this.settings = const GallerySettings(), super.key});

  final GallerySettings settings;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final _settings = ValueNotifier(widget.settings);

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GallerySettingsScope(
    notifier: _settings,
    child: ValueListenableBuilder(
      valueListenable: _settings,
      builder: (context, settings, _) => WidgetsApp(
        title: 'Liquid Glass',
        color: settings.accent.light,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(routeSettings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: routeSettings),
        builder: (context, child) => AnimatedGlassTheme(
          data: GlassThemeData(
            renderer: settings.renderer.renderer,
            brightness: settings.brightness,
            primaryColor: settings.accent.color,
          ),
          child: GlassTraitsOverride(
            reduceTransparency: settings.reduceTransparency ? true : null,
            showBorders: settings.showBorders ? true : null,
            prefersCrossFade: settings.crossFade ? true : null,
            child: _Ambient(child: child!),
          ),
        ),
        home: const GalleryHome(),
      ),
    ),
  );
}

/// The text and icon style of everything the gallery draws itself.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: TextStyle(
      color: GlassDynamicColor.resolve(GlassColors.label, context),
    ),
    child: GlassDefaultTextStyle(
      role: GlassTextRole.body,
      child: IconTheme(
        data: IconThemeData(
          color: GlassDynamicColor.resolve(GlassColors.label, context),
          size: 22,
        ),
        child: child,
      ),
    ),
  );
}

enum GalleryTab { liquid, controls, present, photos }

class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  var _tab = GalleryTab.liquid;
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
          icon: Icon(CupertinoIcons.drop),
          selectedIcon: Icon(CupertinoIcons.drop_fill),
          label: Text('Liquid'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.slider_horizontal_3),
          label: Text('Controls'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.square_stack_3d_up),
          selectedIcon: Icon(CupertinoIcons.square_stack_3d_up_fill),
          label: Text('Present'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.photo_on_rectangle),
          selectedIcon: Icon(CupertinoIcons.photo_fill_on_rectangle_fill),
          label: Text('Photos'),
          badge: Text('6'),
        ),
      ],
      selectedIndex: _tab.index,
      onDestinationSelected: (index) =>
          setState(() => _tab = GalleryTab.values[index]),
      searchController: _search,
    ),
    tabBuilder: (context, index) => switch (GalleryTab.values[index]) {
      GalleryTab.liquid => const LiquidPage(),
      GalleryTab.controls => const ControlsPage(),
      GalleryTab.present => const PresentPage(),
      GalleryTab.photos => const PhotosPage(),
    },
    searchBuilder: (context) => SearchPage(controller: _search, onOpen: _open),
  );
}
