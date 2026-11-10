import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/home.dart';
import 'package:apple_liquid_glass_example/scenes/scene.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Everything in the gallery, found by name: the scenes, the families of
/// widgets with the class names in them, and the two tabs that explain.
class GallerySearchPage extends StatelessWidget {
  const GallerySearchPage({
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final GlassSearchController controller;

  /// Opens a tab.
  final ValueChanged<GalleryTab> onOpen;

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(
      context,
      rootNavigator: true,
    ).push(GlassPageRoute<void>(builder: (context) => page));
    final entries = <(IconData, Color, String, String, VoidCallback)>[
      for (final scene in GalleryScene.all)
        (
          CupertinoIcons.sparkles,
          const Color(0xFF5E5CE6),
          scene.title,
          scene.shows,
          () => push(scene.build(false)),
        ),
      for (final (icon, color, title, widgets, page) in ComponentsPage.families)
        (icon, color, title, widgets, () => push(page())),
      (
        CupertinoIcons.drop_fill,
        GlassColors.systemBlue,
        'Glass',
        'Refraction, clear and regular, tint, outlines, fusing, renderers',
        () => onOpen(GalleryTab.glass),
      ),
      (
        CupertinoIcons.wind,
        GlassColors.systemGray,
        'Motion',
        'Springs, layouts that animate, a control of your own, a replay',
        () => onOpen(GalleryTab.motion),
      ),
    ];
    return GlassPageScaffold(
      backgroundColor: GlassColors.systemGroupedBackground,
      navigationBar: const GlassNavigationBar(largeTitle: Text('Search')),
      child: GlassContentScroll(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final query = controller.text.trim().toLowerCase();
            final found = [
              for (final entry in entries)
                if ('${entry.$3} ${entry.$4}'.toLowerCase().contains(query))
                  entry,
            ];
            return ListView(
              children: [
                if (found.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No Results', textAlign: TextAlign.center),
                  )
                else
                  GlassListSection(
                    header: Text(query.isEmpty ? 'Everything' : 'Results'),
                    children: [
                      for (final (icon, color, title, subtitle, open) in found)
                        GlassListRow(
                          leading: SettingsIcon(icon: icon, color: color),
                          title: Text(title),
                          subtitle: Text(subtitle),
                          accessory: GlassListAccessory.disclosureIndicator,
                          onPressed: open,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
