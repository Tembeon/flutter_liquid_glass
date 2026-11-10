import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/scenes/scene.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/settings_sheet.dart';
import 'package:apple_liquid_glass_example/showcase/cover.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the package can do, a screen at a time: the cover, then every
/// scene playing itself. A swipe turns the page, the button opens the
/// scene to play with, and the switch at the top draws all of it flat
/// instead of in glass, with the same widgets and the same motion.
class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key});

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  final _pages = PageController();
  var _page = 0;

  static const _scenes = GalleryScene.all;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(GalleryScene scene) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(GlassPageRoute<void>(builder: (context) => scene.build(false)));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scene = _page == 0 ? null : _scenes[_page - 1];
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: _scenes.length + 1,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => index == 0
                    ? const Cover()
                    : _Preview(
                        scene: _scenes[index - 1],
                        live: index == _page,
                        media: media,
                      ),
              ),
              // The words below stay readable over any scene.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, 0.1),
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0xC7000000),
                        Color(0xE0000000),
                      ],
                      stops: [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: media.padding.top + 8,
                left: 16,
                right: 16,
                child: _top(context),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: media.padding.bottom + 14,
                child: _caption(scene),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _top(BuildContext context) {
    final settings = GallerySettingsScope.of(context).value;
    return Row(
      children: [
        SizedBox(
          width: 168,
          child: GlassSegmentedControl<bool>(
            segments: const [
              GlassSegment(value: true, label: Text('Glass')),
              GlassSegment(value: false, label: Text('Flat')),
            ],
            groupValue: settings.renderer != GalleryRenderer.flat,
            semanticLabel: 'Renderer',
            onChanged: (glass) => GallerySettingsScope.update(
              context,
              (settings) => settings.copyWith(
                renderer: glass ? GalleryRenderer.liquid : GalleryRenderer.flat,
              ),
            ),
          ),
        ),
        const Spacer(),
        GlassButton(
          onPressed: () => showGallerySettings(context),
          semanticLabel: 'Settings',
          child: const Icon(CupertinoIcons.gear),
        ),
      ],
    );
  }

  Widget _caption(GalleryScene? scene) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomLeft,
          children: [...previous, ?current],
        ),
        child: Column(
          key: ValueKey(_page),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (scene != null)
              Text(
                scene.title,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              scene?.shows ??
                  "iOS 26 glass and UIKit's springs as Flutter widgets. "
                      'Swipe to see what they can do.',
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontSize: 17,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          if (scene != null)
            GlassButton.prominent(
              onPressed: () => _open(scene),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('Open'),
              ),
            )
          else
            const PhotoText('Swipe', size: 17, weight: FontWeight.w600),
          const Spacer(),
          GlassPageControl(
            count: _scenes.length + 1,
            page: _page,
            semanticLabel: 'Scene',
            onChanged: (page) => _pages.animateToPage(
              page,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    ],
  );
}

/// A scene playing itself in the room the showcase leaves it: below the
/// switch, above the caption. It takes no touches; the page under it does.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.scene,
    required this.live,
    required this.media,
  });

  final GalleryScene scene;
  final bool live;
  final MediaQueryData media;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: media.copyWith(
      padding: media.padding.copyWith(
        top: media.padding.top + 56,
        bottom: media.padding.bottom + 150,
      ),
    ),
    child: IgnorePointer(
      child: TickerMode(enabled: live, child: scene.build(true)),
    ),
  );
}
