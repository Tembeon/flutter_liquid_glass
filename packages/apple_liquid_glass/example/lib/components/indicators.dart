import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

class ActivityIndicatorPage extends StatefulWidget {
  const ActivityIndicatorPage({super.key});

  @override
  State<ActivityIndicatorPage> createState() => _ActivityIndicatorPageState();
}

class _ActivityIndicatorPageState extends State<ActivityIndicatorPage> {
  var _animating = true;
  var _hides = true;
  var _size = GlassActivityIndicatorSize.medium;
  var _brand = Brand.system;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassActivityIndicator',
    summary:
        'Eight spokes whose brightest one turns round while a task runs, '
        'in steps of half a spoke, a turn every 0.8 s.',
    stage: GlassActivityIndicator(
      animating: _animating,
      hidesWhenStopped: _hides,
      size: _size,
      color: _brand.color,
    ),
    stageHeight: 120,
    knobs: [
      ToggleKnob(
        'Turning',
        value: _animating,
        onChanged: (on) => setState(() => _animating = on),
      ),
      ToggleKnob(
        'Hidden while stopped',
        value: _hides,
        onChanged: (on) => setState(() => _hides = on),
      ),
      ChoiceKnob<GlassActivityIndicatorSize>(
        'Size',
        value: _size,
        options: const {
          GlassActivityIndicatorSize.medium: 'Medium',
          GlassActivityIndicatorSize.large: 'Large',
        },
        onChanged: (size) => setState(() => _size = size),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
    ideas: [
      Idea(
        'In a row',
        'The trailing end of a row while its value loads.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              leading: const SettingsIcon(
                icon: CupertinoIcons.cloud_fill,
                color: GlassColors.systemBlue,
              ),
              title: const Text('Backup'),
              trailing: GlassActivityIndicator(animating: _animating),
            ),
          ],
        ),
      ),
    ],
  );
}

class ProgressViewPage extends StatefulWidget {
  const ProgressViewPage({super.key});

  @override
  State<ProgressViewPage> createState() => _ProgressViewPageState();
}

class _ProgressViewPageState extends State<ProgressViewPage> {
  var _value = 0.4;
  var _animated = true;
  var _bar = false;
  var _brand = Brand.system;
  var _download = 0.0;
  Timer? _ticks;
  DateTime? _steeped;

  @override
  void dispose() {
    _ticks?.cancel();
    super.dispose();
  }

  void _start() {
    _ticks?.cancel();
    setState(() => _download = 0);
    _ticks = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      setState(() => _download = (_download + 0.13).clamp(0, 1));
      if (_download >= 1) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassProgressView',
    summary:
        'A bar that fills as far as a task has come; a change moves a bar '
        'a second, and changes that overlap add up.',
    stage: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GlassProgressView(
        value: _value,
        animated: _animated,
        style: _bar
            ? GlassProgressViewStyle.bar
            : GlassProgressViewStyle.standard,
        progressColor: _brand.color,
        semanticLabel: 'Progress',
      ),
    ),
    stageHeight: 120,
    knobs: [
      AmountKnob(
        'Progress',
        value: _value,
        onChanged: (value) => setState(() => _value = value),
      ),
      ToggleKnob(
        'Animated',
        value: _animated,
        onChanged: (on) => setState(() => _animated = on),
      ),
      ToggleKnob(
        'Bar style',
        value: _bar,
        onChanged: (on) => setState(() => _bar = on),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
    ideas: [
      Idea(
        'A download',
        'Steps of 13 percent every 0.4 s: each runs on from where the last '
            'one was going.',
        child: Stage(
          height: null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassProgressView(value: _download, semanticLabel: 'Download'),
                const SizedBox(height: 16),
                Center(
                  child: GlassButton(
                    onPressed: _start,
                    child: Text(_download >= 1 ? 'Again' : 'Download'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Idea(
        'Over a time interval',
        'GlassProgressView.timer empties over the time a task takes, here '
            'eight seconds of steeping, at a constant speed.',
        child: Stage(
          height: null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_steeped case final start?)
                  GlassProgressView.timer(
                    start: start,
                    end: start.add(const Duration(seconds: 8)),
                    semanticLabel: 'Tea',
                  )
                else
                  const GlassProgressView(value: 1, semanticLabel: 'Tea'),
                const SizedBox(height: 16),
                Center(
                  child: GlassButton(
                    onPressed: () => setState(() => _steeped = DateTime.now()),
                    child: const Text('Steep'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class RefreshControlPage extends StatefulWidget {
  const RefreshControlPage({super.key});

  @override
  State<RefreshControlPage> createState() => _RefreshControlPageState();
}

class _RefreshControlPageState extends State<RefreshControlPage> {
  var _titled = false;
  var _brand = Brand.system;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSliverRefreshControl',
    summary:
        'Ticks that come in with the pull at the top of a scroll view; a '
        'pull of 174 points starts the refresh and they turn until it '
        'ends.',
    stageHeight: 130,
    stage: GlassButton.prominent(
      onPressed: () => unawaited(
        Navigator.of(context, rootNavigator: true).push(
          GlassPageRoute<void>(
            builder: (context) =>
                _Letters(titled: _titled, color: _brand.color),
          ),
        ),
      ),
      child: const Text('Open the letters'),
    ),
    knobs: [
      ToggleKnob(
        'Title under the ticks',
        value: _titled,
        onChanged: (on) => setState(() => _titled = on),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
  );
}

/// A page of letters to pull down for more: the refresh control needs the
/// page's own scroll view, whose height its pull is measured against.
class _Letters extends StatefulWidget {
  const _Letters({required this.titled, required this.color});

  final bool titled;
  final Color? color;

  @override
  State<_Letters> createState() => _LettersState();
}

class _LettersState extends State<_Letters> {
  var _letters = 6;

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _letters++);
  }

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: const GlassNavigationBar(
      title: Text('Letters'),
      previousPageTitle: 'Refresh',
    ),
    child: GlassContentScroll(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          GlassSliverRefreshControl(
            onRefresh: _refresh,
            color: widget.color,
            title: widget.titled ? const Text('Fetching letters') : null,
          ),
          SliverToBoxAdapter(
            child: GlassListSection(
              header: const Text('Pull down to refresh'),
              children: [
                for (var i = _letters; i > 0; i--)
                  GlassListRow(
                    leading: const SettingsIcon(
                      icon: CupertinoIcons.envelope_fill,
                      color: GlassColors.systemBlue,
                    ),
                    title: Text('Letter $i'),
                    subtitle: const Text('A pull of 174 points fetches more'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class PageViewPage extends StatefulWidget {
  const PageViewPage({super.key});

  @override
  State<PageViewPage> createState() => _PageViewPageState();
}

class _PageViewPageState extends State<PageViewPage> {
  final _pages = PageController();
  var _page = 0;
  var _uikit = true;

  static const _colors = [
    GlassColors.systemBlue,
    GlassColors.systemGreen,
    GlassColors.systemOrange,
    GlassColors.systemRed,
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassPageScrollPhysics',
    summary:
        "UIKit's paging for a PageView: a release faster than 300 points a "
        'second turns a page whatever the distance, and every settle takes '
        'the same 0.35 s spring.',
    stageHeight: 260,
    stage: SizedBox(
      height: 220,
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              pageSnapping: !_uikit,
              physics: _uikit ? const GlassPageScrollPhysics() : null,
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                for (final (i, color) in _colors.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: GlassDynamicColor.resolve(color, context),
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Page ${i + 1}',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassPageControl(
            count: _colors.length,
            page: _page,
            onChanged: (page) => _pages.animateToPage(
              page,
              duration: GlassPageScrollPhysics.turnFromCode.duration,
              curve: GlassPageScrollPhysics.turnFromCode.curve,
            ),
          ),
        ],
      ),
    ),
    knobs: [
      ChoiceKnob<bool>(
        'Paging',
        value: _uikit,
        options: const {true: "UIKit's", false: "Flutter's"},
        onChanged: (uikit) => setState(() => _uikit = uikit),
      ),
    ],
  );
}
