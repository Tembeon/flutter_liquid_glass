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
  String? _lastHaptic;
  int _hapticSeq = 0;

  void _toggleSlowMo() {
    setState(() {
      _slowMo = !_slowMo;
      timeDilation = _slowMo ? 4.0 : 1.0;
    });
  }

  void _onHaptic(MotionHaptic haptic) {
    if (!mounted) return;
    setState(() {
      _lastHaptic = haptic.name;
      _hapticSeq++;
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
      child: MotionTraitsOverride(
        traits: MotionTraits(
          reduceMotion: _reduceMotion,
          preferCrossFade: _reduceMotion,
        ),
        child: MotionHapticScope(
          enabled: true,
          onFeedback: _onHaptic,
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
              lastHaptic: _lastHaptic,
              hapticSeq: _hapticSeq,
              onSelectTab: (next) => setState(() => _tab = next),
              onToggleDark: () => setState(() => _dark = !_dark),
              onToggleReduceMotion: () =>
                  setState(() => _reduceMotion = !_reduceMotion),
              onToggleSlowMo: _toggleSlowMo,
              page: _buildPage(_tab),
            ),
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
    required this.lastHaptic,
    required this.hapticSeq,
    required this.onSelectTab,
    required this.onToggleDark,
    required this.onToggleReduceMotion,
    required this.onToggleSlowMo,
    required this.page,
  });

  final StudioTab tab;
  final bool dark;
  final bool reduceMotion;
  final bool slowMo;
  final String? lastHaptic;
  final int hapticSeq;
  final ValueChanged<StudioTab> onSelectTab;
  final VoidCallback onToggleDark;
  final VoidCallback onToggleReduceMotion;
  final VoidCallback onToggleSlowMo;
  final Widget page;

  static const _tabs = [
    SegmentedItem<StudioTab>(
      value: StudioTab.springs,
      label: 'Springs',
      glyph: StudioGlyph.spring,
    ),
    SegmentedItem<StudioTab>(
      value: StudioTab.animator,
      label: 'Animator',
      glyph: StudioGlyph.timeline,
    ),
    SegmentedItem<StudioTab>(
      value: StudioTab.scroll,
      label: 'Scroll',
      glyph: StudioGlyph.scroll,
    ),
    SegmentedItem<StudioTab>(
      value: StudioTab.text,
      label: 'Text',
      glyph: StudioGlyph.text,
    ),
    SegmentedItem<StudioTab>(
      value: StudioTab.symbols,
      label: 'Symbols',
      glyph: StudioGlyph.sparkle,
    ),
    SegmentedItem<StudioTab>(
      value: StudioTab.layout,
      label: 'Layout',
      glyph: StudioGlyph.grid,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.AppleSystemUIFont',
        fontSize: 14,
        color: palette.textPrimary,
      ),
      child: ColoredBox(
        color: palette.canvas,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border(bottom: BorderSide(color: palette.hairline)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [palette.blue, palette.indigo],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(7),
                                      child: StudioIcon(
                                        StudioGlyph.spring,
                                        color: Color(0xFFFFFFFF),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Kinesis Studio',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '100% pure kinesis + flutter/widgets',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: palette.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (lastHaptic case final name?)
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: palette.teal.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        child: MotionContentTransition(
                                          transition:
                                              const ContentTransition.fade(),
                                          child: Text(
                                            'haptic: $name',
                                            key: ValueKey<int>(hapticSeq),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: palette.teal,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  KinesisChip(
                                    label: slowMo ? '0.25x Slow' : '1x Speed',
                                    selected: slowMo,
                                    accent: palette.orange,
                                    onTap: onToggleSlowMo,
                                  ),
                                  KinesisChip(
                                    label: 'Reduce Motion',
                                    selected: reduceMotion,
                                    accent: palette.purple,
                                    onTap: onToggleReduceMotion,
                                  ),
                                  KinesisChip(
                                    label: dark ? 'Dark' : 'Light',
                                    glyph: dark
                                        ? StudioGlyph.moon
                                        : StudioGlyph.sun,
                                    selected: dark,
                                    onTap: onToggleDark,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          KinesisSegmentedBar<StudioTab>(
                            items: _tabs,
                            value: tab,
                            onChanged: onSelectTab,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: MotionContentTransition(
                              transition: const ContentTransition.fade(),
                              child: KeyedSubtree(
                                key: ValueKey<StudioTab>(tab),
                                child: page,
                              ),
                            ),
                          ),
                        ),
                      ),
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
