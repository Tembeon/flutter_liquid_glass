import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/pages/animator_page.dart';
import 'package:kinesis_example/pages/layout_page.dart';
import 'package:kinesis_example/pages/scroll_page.dart';
import 'package:kinesis_example/pages/springs_page.dart';
import 'package:kinesis_example/pages/symbols_page.dart';
import 'package:kinesis_example/pages/text_page.dart';
import 'package:kinesis_example/theme.dart';

enum StudioTab { springs, animator, scroll, text, symbols, layout }

final class _NavSpec {
  const _NavSpec({
    required this.tab,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.glyph,
    required this.accent,
  });

  final StudioTab tab;
  final String title;
  final String shortTitle;
  final String subtitle;
  final StudioGlyph glyph;
  final Color Function(StudioPalette palette) accent;
}

Color _blue(StudioPalette palette) => palette.blue;
Color _pink(StudioPalette palette) => palette.pink;
Color _orange(StudioPalette palette) => palette.orange;
Color _purple(StudioPalette palette) => palette.purple;
Color _indigo(StudioPalette palette) => palette.indigo;
Color _teal(StudioPalette palette) => palette.teal;

_NavSpec _specOf(StudioTab tab) =>
    _navItems.firstWhere((item) => item.tab == tab);

final class _PageRise extends ContentTransition {
  const _PageRise();

  @override
  MotionPose poseAt(double progress, {required bool incoming}) {
    final p = progress.clamp(0.0, 1.0);
    return incoming
        ? MotionPose(
            offset: Offset(0, 28 * (1 - p)),
            opacity: p,
            blur: 8 * (1 - p),
          )
        : MotionPose(scale: 1 - 0.03 * p, opacity: 1 - p, blur: 4 * p);
  }

  @override
  AlignmentGeometry get alignment => Alignment.topCenter;
}

const _navItems = [
  _NavSpec(
    tab: StudioTab.springs,
    title: 'Picture-in-Picture',
    shortTitle: 'PiP',
    subtitle: 'Gestures & springs',
    glyph: StudioGlyph.pip,
    accent: _blue,
  ),
  _NavSpec(
    tab: StudioTab.animator,
    title: 'Now Playing',
    shortTitle: 'Player',
    subtitle: 'Scrub & keyframes',
    glyph: StudioGlyph.music,
    accent: _pink,
  ),
  _NavSpec(
    tab: StudioTab.scroll,
    title: 'Carousel & Feed',
    shortTitle: 'Scroll',
    subtitle: 'Paging & momentum',
    glyph: StudioGlyph.scroll,
    accent: _orange,
  ),
  _NavSpec(
    tab: StudioTab.text,
    title: 'Live Typography',
    shortTitle: 'Text',
    subtitle: 'Digits, morph & caret',
    glyph: StudioGlyph.text,
    accent: _purple,
  ),
  _NavSpec(
    tab: StudioTab.symbols,
    title: 'Tactile Symbols',
    shortTitle: 'Symbols',
    subtitle: 'Effects & haptics',
    glyph: StudioGlyph.sparkle,
    accent: _indigo,
  ),
  _NavSpec(
    tab: StudioTab.layout,
    title: 'Fluid Layout',
    shortTitle: 'Layout',
    subtitle: 'Grid, dock & overlays',
    glyph: StudioGlyph.grid,
    accent: _teal,
  ),
];

class KinesisStudioApp extends StatefulWidget {
  const KinesisStudioApp({super.key});

  @override
  State<KinesisStudioApp> createState() => _KinesisStudioAppState();
}

class _KinesisStudioAppState extends State<KinesisStudioApp> {
  StudioTab _tab = StudioTab.springs;
  bool _dark = false;
  bool _reduceMotion = false;
  bool _slowMo = false;
  bool _inspector = false;

  void _toggleSlowMo(bool value) {
    setState(() {
      _slowMo = value;
      timeDilation = _slowMo ? 4.0 : 1.0;
    });
  }

  @override
  void dispose() {
    if (_slowMo) {
      timeDilation = 1.0;
    }
    super.dispose();
  }

  Widget _buildPage(StudioTab tab) => switch (tab) {
    StudioTab.springs => const SpringsPage(),
    StudioTab.animator => const AnimatorPage(),
    StudioTab.scroll => const ScrollPage(),
    StudioTab.text => const TextPage(),
    StudioTab.symbols => const SymbolsPage(),
    StudioTab.layout => const LayoutPage(),
  };

  @override
  Widget build(BuildContext context) {
    final palette = _dark ? StudioPalette.dark : StudioPalette.light;
    return StudioTheme(
      palette: palette,
      inspector: _inspector,
      child: MotionTraitsOverride(
        traits: MotionTraits(
          reduceMotion: _reduceMotion,
          preferCrossFade: _reduceMotion,
        ),
        child: WidgetsApp(
          title: 'Kinesis Studio',
          color: palette.blue,
          debugShowCheckedModeBanner: false,
          pageRouteBuilder:
              <T>(RouteSettings settings, WidgetBuilder builder) =>
                  PageRouteBuilder<T>(
                    settings: settings,
                    pageBuilder: (context, _, _) => builder(context),
                  ),
          home: _StudioShell(
            tab: _tab,
            dark: _dark,
            reduceMotion: _reduceMotion,
            slowMo: _slowMo,
            inspector: _inspector,
            onSelectTab: (next) => setState(() => _tab = next),
            onToggleDark: () => setState(() => _dark = !_dark),
            onToggleReduceMotion: (v) => setState(() => _reduceMotion = v),
            onToggleSlowMo: _toggleSlowMo,
            onToggleInspector: (v) => setState(() => _inspector = v),
            page: _buildPage(_tab),
          ),
        ),
      ),
    );
  }
}

class _StudioShell extends StatelessWidget {
  const _StudioShell({
    required this.tab,
    required this.dark,
    required this.reduceMotion,
    required this.slowMo,
    required this.inspector,
    required this.onSelectTab,
    required this.onToggleDark,
    required this.onToggleReduceMotion,
    required this.onToggleSlowMo,
    required this.onToggleInspector,
    required this.page,
  });

  final StudioTab tab;
  final bool dark;
  final bool reduceMotion;
  final bool slowMo;
  final bool inspector;
  final ValueChanged<StudioTab> onSelectTab;
  final VoidCallback onToggleDark;
  final ValueChanged<bool> onToggleReduceMotion;
  final ValueChanged<bool> onToggleSlowMo;
  final ValueChanged<bool> onToggleInspector;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: 14,
        color: palette.textPrimary,
      ),
      child: ColoredBox(
        color: palette.canvas,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= studioWideFrom;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(
                      tab: tab,
                      dark: dark,
                      reduceMotion: reduceMotion,
                      slowMo: slowMo,
                      inspector: inspector,
                      onSelectTab: onSelectTab,
                      onToggleDark: onToggleDark,
                      onToggleReduceMotion: onToggleReduceMotion,
                      onToggleSlowMo: onToggleSlowMo,
                      onToggleInspector: onToggleInspector,
                    ),
                    Expanded(
                      child: _PageViewport(tab: tab, page: page),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CompactTopBar(
                    dark: dark,
                    slowMo: slowMo,
                    inspector: inspector,
                    onToggleDark: onToggleDark,
                    onToggleSlowMo: () => onToggleSlowMo(!slowMo),
                    onToggleInspector: () => onToggleInspector(!inspector),
                  ),
                  Expanded(
                    child: _PageViewport(tab: tab, page: page),
                  ),
                  _CompactBottomBar(tab: tab, onSelectTab: onSelectTab),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PageViewport extends StatelessWidget {
  const _PageViewport({required this.tab, required this.page});

  final StudioTab tab;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final spec = _specOf(tab);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: narrow
              ? const EdgeInsets.fromLTRB(16, 20, 16, 32)
              : const EdgeInsets.fromLTRB(36, 36, 36, 48),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: studioPageMaxWidth,
                ),
                child: MotionContentTransition(
                  transition: const _PageRise(),
                  alignment: Alignment.topCenter,
                  child: StudioPageInfo(
                    key: ValueKey<StudioTab>(tab),
                    eyebrow: spec.subtitle,
                    accent: spec.accent(StudioTheme.of(context)),
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.tab,
    required this.dark,
    required this.reduceMotion,
    required this.slowMo,
    required this.inspector,
    required this.onSelectTab,
    required this.onToggleDark,
    required this.onToggleReduceMotion,
    required this.onToggleSlowMo,
    required this.onToggleInspector,
  });

  final StudioTab tab;
  final bool dark;
  final bool reduceMotion;
  final bool slowMo;
  final bool inspector;
  final ValueChanged<StudioTab> onSelectTab;
  final VoidCallback onToggleDark;
  final ValueChanged<bool> onToggleReduceMotion;
  final ValueChanged<bool> onToggleSlowMo;
  final ValueChanged<bool> onToggleInspector;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  static const double _rowHeight = 52;

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _activeRow = MotionValue<double>(
    widget.tab.index.toDouble(),
    restDistance: MotionRest.scale(_rowHeight),
    clock: _clock,
  );

  @override
  void didUpdateWidget(_Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      withSpring(
        Spring.snappy,
        () => _activeRow.retarget(_clock.now, widget.tab.index.toDouble()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(right: BorderSide(color: palette.hairline)),
      ),
      child: SizedBox(
        width: 244,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [palette.blue, palette.indigo],
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: StudioIcon(
                          StudioGlyph.sparkle,
                          color: Color(0xFFFFFFFF),
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kinesis',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text('Motion Studio', style: palette.caption),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: _navItems.length * _rowHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SidebarPillPainter(
                          row: _activeRow,
                          rowHeight: _rowHeight,
                          color: palette.surface,
                          border: palette.hairline,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        for (final item in _navItems)
                          _SidebarItem(
                            spec: item,
                            height: _rowHeight,
                            selected: widget.tab == item.tab,
                            onTap: () => widget.onSelectTab(item.tab),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ToggleRow(
                        label: 'Slow Motion (0.25x)',
                        value: widget.slowMo,
                        accent: palette.orange,
                        onChanged: widget.onToggleSlowMo,
                      ),
                      const SizedBox(height: 10),
                      _ToggleRow(
                        label: 'Reduce Motion',
                        value: widget.reduceMotion,
                        accent: palette.purple,
                        onChanged: widget.onToggleReduceMotion,
                      ),
                      const SizedBox(height: 10),
                      _ToggleRow(
                        label: 'Inspector',
                        value: widget.inspector,
                        accent: palette.blue,
                        onChanged: widget.onToggleInspector,
                      ),
                      const SizedBox(height: 12),
                      KinesisButton(
                        label: widget.dark ? 'Dark Mode' : 'Light Mode',
                        glyph: widget.dark ? StudioGlyph.moon : StudioGlyph.sun,
                        compact: true,
                        onPressed: widget.onToggleDark,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.spec,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final _NavSpec spec;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return InputRegion(
      interactions: [TapInteraction(onTap: (_) => onTap())],
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.selection : null,
      semantics: SemanticsProperties(
        button: true,
        selected: selected,
        label: spec.title,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              StudioIcon(
                spec.glyph,
                size: 18,
                color: selected ? spec.accent(palette) : palette.textSecondary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                    Text(
                      spec.subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: palette.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SidebarPillPainter extends CustomPainter {
  _SidebarPillPainter({
    required this.row,
    required this.rowHeight,
    required this.color,
    required this.border,
  }) : super(repaint: row);

  final MotionValue<double> row;
  final double rowHeight;
  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final top = row.value * rowHeight + 2;
    final rect = Rect.fromLTWH(0, top, size.width, rowHeight - 4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()..color = const Color(0x10000000),
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SidebarPillPainter oldDelegate) =>
      color != oldDelegate.color || border != oldDelegate.border;
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        KinesisSwitch(
          value: value,
          accent: accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _CompactTopBar extends StatelessWidget {
  const _CompactTopBar({
    required this.dark,
    required this.slowMo,
    required this.inspector,
    required this.onToggleDark,
    required this.onToggleSlowMo,
    required this.onToggleInspector,
  });

  final bool dark;
  final bool slowMo;
  final bool inspector;
  final VoidCallback onToggleDark;
  final VoidCallback onToggleSlowMo;
  final VoidCallback onToggleInspector;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Text(
              'Kinesis',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                KinesisChip(
                  label: slowMo ? '0.25x' : '1x',
                  selected: slowMo,
                  accent: palette.orange,
                  onTap: onToggleSlowMo,
                ),
                KinesisChip(
                  label: 'Inspect',
                  selected: inspector,
                  onTap: onToggleInspector,
                ),
                KinesisChip(
                  label: dark ? 'Dark' : 'Light',
                  glyph: dark ? StudioGlyph.moon : StudioGlyph.sun,
                  selected: dark,
                  onTap: onToggleDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactBottomBar extends StatefulWidget {
  const _CompactBottomBar({
    required this.tab,
    required this.onSelectTab,
  });

  final StudioTab tab;
  final ValueChanged<StudioTab> onSelectTab;

  @override
  State<_CompactBottomBar> createState() => _CompactBottomBarState();
}

class _CompactBottomBarState extends State<_CompactBottomBar> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _active = MotionValue<double>(
    widget.tab.index.toDouble(),
    restDistance: MotionRest.scale(studioWideFrom / _navItems.length),
    clock: _clock,
  );

  @override
  void didUpdateWidget(_CompactBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      withSpring(
        Spring.snappy,
        () => _active.retarget(_clock.now, widget.tab.index.toDouble()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: SizedBox(
          height: 50,
          child: CustomPaint(
            painter: _BarPillPainter(
              column: _active,
              colors: [
                for (final item in _navItems)
                  item.accent(palette).withValues(alpha: 0.14),
              ],
            ),
            child: Row(
              children: [
                for (final item in _navItems)
                  Expanded(
                    child: _BarItem(
                      spec: item,
                      selected: widget.tab == item.tab,
                      onTap: () => widget.onSelectTab(item.tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final color = selected ? spec.accent(palette) : palette.textTertiary;
    return InputRegion(
      interactions: [TapInteraction(onTap: (_) => onTap())],
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.selection : null,
      semantics: SemanticsProperties(
        button: true,
        selected: selected,
        label: spec.title,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StudioIcon(spec.glyph, size: 20, color: color),
          const SizedBox(height: 3),
          Text(
            spec.shortTitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

final class _BarPillPainter extends CustomPainter {
  _BarPillPainter({required this.column, required this.colors})
    : super(repaint: column);

  final MotionValue<double> column;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width / colors.length;
    final at = column.value.clamp(0.0, colors.length - 1.0);
    final below = at.floor();
    final above = at.ceil();
    final color = Color.lerp(colors[below], colors[above], at - below)!;
    final rect = Rect.fromLTWH(at * width + 4, 0, width - 8, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPillPainter oldDelegate) =>
      !listEquals(colors, oldDelegate.colors);
}
