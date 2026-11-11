import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Controls built from Flutter's own blocks that calibrate the checks: the
/// `good` ones meet every check, the `bad` ones break the rules on purpose,
/// so every check is seen to pass and to fail.
final List<Entry> references = [
  Entry(
    'reference.good.button',
    covers: const [],
    kind: Kind.pressable,
    build: (probe, {required enabled}) =>
        _GoodButton(enabled: enabled, onPressed: () => probe.add('pressed')),
  ),
  Entry(
    'reference.good.slider',
    covers: const [],
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 0.5,
      builder: (context, value, set) =>
          _GoodSlider(value: value, onChanged: enabled ? set : null),
    ),
  ),
  Entry(
    'reference.good.dialog',
    covers: const [],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => _dialog(context, probe, overlayText, 'Inside'),
    ),
  ),
  Entry(
    'reference.good.contextMenu',
    covers: const [],
    kind: Kind.opener,
    openGesture: OpenGesture.longPress,
    contextMenu: true,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => _GoodContextMenu(
      enabled: enabled,
      open: (context) => _dialog(context, probe, 'Menu', 'First item'),
    ),
  ),
  Entry(
    'reference.bad.button',
    covers: const [],
    kind: Kind.pressable,
    build: (probe, {required enabled}) =>
        _BadButton(enabled: enabled, onPressed: () => probe.add('pressed')),
  ),
  Entry(
    'reference.bad.slider',
    covers: const [],
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 0.5,
      builder: (context, value, set) =>
          _BadSlider(value: value, onChanged: enabled ? set : null),
    ),
  ),
  Entry(
    'reference.bad.contextMenu',
    covers: const [],
    kind: Kind.opener,
    openGesture: OpenGesture.longPress,
    contextMenu: true,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => Builder(
      builder: (context) => GestureDetector(
        onLongPress: enabled
            ? () => _dialog(context, probe, 'Menu', 'First item')
            : null,
        child: SizedBox(
          width: 120,
          height: 80,
          child: Center(
            child: Text(
              'Photo',
              style: TextStyle(fontSize: 17, color: _ink(context)),
            ),
          ),
        ),
      ),
    ),
  ),
  Entry(
    'reference.bad.overlay',
    covers: const [],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => Overlay.of(context).insert(
        OverlayEntry(
          builder: (context) => Positioned(
            key: ObjectKey(FocusNode()),
            left: 100,
            top: 300,
            child: Column(
              children: [
                const Text(
                  overlayText,
                  style: TextStyle(fontSize: 17, color: Color(0xFFDDDDDD)),
                ),
                ProbeButton(
                  label: 'Inside',
                  onPressed: () => probe.add('inside'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
];

Future<void> _dialog(
  BuildContext context,
  Probe probe,
  String title,
  String inside,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss',
  pageBuilder: (context, animation, secondary) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => ExcludeSemantics(
      excluding: animation.status == AnimationStatus.reverse,
      child: child,
    ),
    child: Center(
      child: ColoredBox(
        color: MediaQuery.platformBrightnessOf(context) == Brightness.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: 'Dialog',
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 17, color: _ink(context)),
              ),
              ProbeButton(label: inside, onPressed: () => probe.add('inside')),
            ],
          ),
        ),
      ),
    ),
  ),
);

class _OpenMenuIntent extends Intent {
  const _OpenMenuIntent();
}

class _GoodContextMenu extends StatefulWidget {
  const _GoodContextMenu({required this.enabled, required this.open});

  final bool enabled;
  final void Function(BuildContext context) open;

  @override
  State<_GoodContextMenu> createState() => _GoodContextMenuState();
}

class _GoodContextMenuState extends State<_GoodContextMenu> {
  bool _focused = false;
  bool _hovered = false;

  void _open() => widget.open(context);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final ink = _ink(context);
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): _OpenMenuIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): _OpenMenuIntent(),
      },
      actions: {
        _OpenMenuIntent: CallbackAction<_OpenMenuIntent>(
          onInvoke: (_) {
            _open();
            return null;
          },
        ),
      },
      child: Semantics(
        enabled: enabled,
        label: 'Reference photo',
        onLongPress: enabled ? _open : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          onLongPress: enabled ? _open : null,
          onSecondaryTap: enabled ? _open : null,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 120,
                height: 80,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      'Photo',
                      style: TextStyle(fontSize: 17, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _ink(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.light
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

Color _faint(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.light
    ? const Color(0xFFDDDDDD)
    : const Color(0xFF222222);

class _GoodButton extends StatefulWidget {
  const _GoodButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_GoodButton> createState() => _GoodButtonState();
}

class _GoodButtonState extends State<_GoodButton> {
  bool _focused = false;
  bool _hovered = false;

  void _tap() {
    HapticFeedback.selectionClick();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final ink = _ink(context);
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Reference',
        onTap: enabled ? widget.onPressed : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: enabled ? _tap : null,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 120,
                height: 44,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      'Reference',
                      style: TextStyle(fontSize: 17, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.by);

  final double by;
}

class _EdgeIntent extends Intent {
  const _EdgeIntent(this.to);

  final double to;
}

class _GoodSlider extends StatefulWidget {
  const _GoodSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  State<_GoodSlider> createState() => _GoodSliderState();
}

class _GoodSliderState extends State<_GoodSlider> {
  bool _focused = false;
  bool _hovered = false;

  void _set(double value) => widget.onChanged?.call(value.clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final ink = _ink(context);
    final forward = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    final value = widget.value;
    String percent(double v) => '${(v.clamp(0, 1) * 100).round()}%';
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(
          0.1 * forward,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(
          -0.1 * forward,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _StepIntent(
          0.1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _StepIntent(
          -0.1,
        ),
        const SingleActivator(LogicalKeyboardKey.home): const _EdgeIntent(0),
        const SingleActivator(LogicalKeyboardKey.end): const _EdgeIntent(1),
      },
      actions: {
        _StepIntent: CallbackAction<_StepIntent>(
          onInvoke: (intent) {
            _set(value + intent.by);
            return null;
          },
        ),
        _EdgeIntent: CallbackAction<_EdgeIntent>(
          onInvoke: (intent) {
            _set(intent.to);
            return null;
          },
        ),
      },
      child: Semantics(
        slider: true,
        enabled: enabled,
        label: 'Reference level',
        value: percent(value),
        increasedValue: percent(value + 0.1),
        decreasedValue: percent(value - 0.1),
        onIncrease: enabled ? () => _set(value + 0.1) : null,
        onDecrease: enabled ? () => _set(value - 0.1) : null,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            excludeFromSemantics: true,
            onTapUp: enabled
                ? (details) {
                    final x = details.localPosition.dx / 300;
                    _set(forward == 1 ? x : 1 - x);
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 300,
                height: 44,
                child: Align(
                  alignment: AlignmentDirectional(value * 2 - 1, 0),
                  child: SizedBox.square(
                    dimension: 24,
                    child: ColoredBox(color: ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadButton extends StatelessWidget {
  const _BadButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  void _tap() {
    HapticFeedback.heavyImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) => Focus(
    child: Semantics(
      onTap: _tap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: _tap,
        child: SizedBox(
          width: 300,
          height: 20,
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  'Bad control label',
                  style: TextStyle(fontSize: 17, color: _faint(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BadSlider extends StatelessWidget {
  const _BadSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => Focus(
    child: Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          onChanged?.call((value + 0.1).clamp(0, 1));
        }
      },
      child: Semantics(
        value: '$value',
        onTap: () => onChanged?.call(1),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => onChanged?.call(1),
          child: SizedBox(
            width: 300,
            height: 20,
            child: Align(
              alignment: AlignmentDirectional(value * 2 - 1, 0),
              child: SizedBox.square(
                dimension: 20,
                child: ColoredBox(color: _faint(context)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
