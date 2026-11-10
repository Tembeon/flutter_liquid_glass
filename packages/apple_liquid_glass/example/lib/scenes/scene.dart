import 'package:apple_liquid_glass_example/scenes/control_center_page.dart';
import 'package:apple_liquid_glass_example/scenes/island_page.dart';
import 'package:apple_liquid_glass_example/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/scenes/lens_page.dart';
import 'package:apple_liquid_glass_example/scenes/lock_screen_page.dart';
import 'package:apple_liquid_glass_example/scenes/pads_page.dart';
import 'package:apple_liquid_glass_example/scenes/weather_page.dart';
import 'package:flutter/widgets.dart';

/// A whole screen built from the package, as the showcase lists it: its
/// name, the strength of the package it shows, and the page, which plays
/// itself when built as a preview.
final class GalleryScene {
  const GalleryScene(this.title, this.shows, this.build);

  final String title;

  /// One line on what to look at.
  final String shows;

  // ignore: avoid_positional_boolean_parameters, the one argument of a scene.
  final Widget Function(bool preview) build;

  static const all = <GalleryScene>[
    GalleryScene(
      'Island',
      'Springs you can interrupt: a shape that stretches, splits and opens.',
      _island,
    ),
    GalleryScene(
      'Lava',
      'Glass that fuses: drops with physics, colors running across the joins.',
      _lava,
    ),
    GalleryScene(
      'Weather',
      'Glass over a living page: a painted sky passing through every rim.',
      _weather,
    ),
    GalleryScene(
      'Pads',
      'Every finger at once: glass that sinks, fills, glows and bends light.',
      _pads,
    ),
    GalleryScene(
      'Control Center',
      'A system screen from surfaces alone, with sliders that stretch.',
      _controlCenter,
    ),
    GalleryScene(
      'Lock Screen',
      'Widgets over a photo and a stack of notifications that fans out.',
      _lockScreen,
    ),
    GalleryScene(
      'Lens',
      'What glass does to the page under it, clear, frosted or tinted.',
      _lens,
    ),
  ];

  static Widget _island(bool preview) => IslandPage(preview: preview);
  static Widget _lava(bool preview) => LavaPage(preview: preview);
  static Widget _weather(bool preview) => WeatherPage(preview: preview);
  static Widget _pads(bool preview) => PadsPage(preview: preview);
  static Widget _controlCenter(bool preview) =>
      ControlCenterPage(preview: preview);
  static Widget _lockScreen(bool preview) => LockScreenPage(preview: preview);
  static Widget _lens(bool preview) => LensPage(preview: preview);
}
