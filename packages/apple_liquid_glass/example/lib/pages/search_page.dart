import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The page of the tab bar's search tab: everything the gallery shows,
/// filtered as you type, each a tap away.
class SearchPage extends StatelessWidget {
  const SearchPage({required this.controller, required this.onOpen, super.key});

  final GlassSearchController controller;
  final ValueChanged<GalleryTab> onOpen;

  static const _features = [
    (
      'Glass drops',
      'Fusing, lift and touch glow',
      GalleryTab.liquid,
      CupertinoIcons.drop_fill,
    ),
    (
      'Renderers',
      'Liquid, fake and flat glass',
      GalleryTab.liquid,
      CupertinoIcons.cube_fill,
    ),
    (
      'Page control',
      'Over a photo carousel',
      GalleryTab.controls,
      CupertinoIcons.circle_grid_3x3_fill,
    ),
    (
      'Switch',
      'The liquid knob',
      GalleryTab.controls,
      CupertinoIcons.switch_camera_solid,
    ),
    (
      'Slider',
      'Continuous and with ticks',
      GalleryTab.controls,
      CupertinoIcons.slider_horizontal_3,
    ),
    (
      'Stepper',
      'Minus and plus on one glass',
      GalleryTab.controls,
      CupertinoIcons.plus_slash_minus,
    ),
    (
      'Segmented control',
      'A lens slides between segments',
      GalleryTab.controls,
      CupertinoIcons.rectangle_split_3x1_fill,
    ),
    (
      'Buttons',
      'Glass, prominent and clear',
      GalleryTab.controls,
      CupertinoIcons.capsule_fill,
    ),
    (
      'Date picker',
      'Compact, inline and wheels',
      GalleryTab.controls,
      CupertinoIcons.calendar,
    ),
    (
      'Lists',
      'Grouped rows and accessories',
      GalleryTab.controls,
      CupertinoIcons.list_bullet,
    ),
    (
      'Menus',
      'Sections, submenus, palettes',
      GalleryTab.present,
      CupertinoIcons.ellipsis_circle_fill,
    ),
    (
      'Context menu',
      'Hold a photo',
      GalleryTab.present,
      CupertinoIcons.hand_draw_fill,
    ),
    (
      'Alert',
      'And the action sheet',
      GalleryTab.present,
      CupertinoIcons.exclamationmark_bubble_fill,
    ),
    (
      'Popover',
      'Anchored to its button',
      GalleryTab.present,
      CupertinoIcons.text_bubble_fill,
    ),
    (
      'Sheet',
      'Detents and a guarded draft',
      GalleryTab.present,
      CupertinoIcons.rectangle_dock,
    ),
    (
      'Zoom transition',
      'A photo grows into its page',
      GalleryTab.photos,
      CupertinoIcons.arrow_up_left_arrow_down_right,
    ),
    (
      'Toolbar',
      'Glass items that fuse',
      GalleryTab.photos,
      CupertinoIcons.rectangle_3_offgrid_fill,
    ),
    (
      'Tab bar',
      'Minimizes on scroll, with an accessory',
      GalleryTab.present,
      CupertinoIcons.square_grid_2x2_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: const GlassNavigationBar(largeTitle: Text('Search')),
    child: GlassContentScroll(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final query = controller.text.trim().toLowerCase();
          final found = [
            for (final feature in _features)
              if ('${feature.$1} ${feature.$2}'.toLowerCase().contains(query))
                feature,
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
                    for (final (title, subtitle, tab, icon) in found)
                      GlassListRow(
                        leading: SettingsIcon(
                          icon: icon,
                          color: switch (tab) {
                            GalleryTab.liquid => GlassColors.systemBlue,
                            GalleryTab.controls => GlassColors.systemGreen,
                            GalleryTab.present => GlassColors.systemOrange,
                            GalleryTab.photos => GlassColors.systemRed,
                          },
                        ),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        accessory: GlassListAccessory.disclosureIndicator,
                        onPressed: () => onOpen(tab),
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
