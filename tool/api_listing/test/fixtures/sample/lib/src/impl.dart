import 'package:dep/dep.dart';
import 'package:dep/src/hidden.dart';
import 'package:meta/meta.dart';

class _Base {
  Object make() => Object();
}

class Engine {}

enum Mode {
  slow,
  fast;

  factory Mode.of(bool quick) => quick ? fast : slow;
}

class Widget extends _Base {
  Widget(
    this.size, {
    required this.mode,
    this.label = 'x',
    @internal Engine? engine,
  });

  final int size;

  final Mode mode;

  final String label;

  Hidden get hidden => Hidden();

  Shown shown<T extends Object>(T value) => Shown();

  @internal
  Engine get engine => Engine();

  @override
  Engine make() => Engine();

  @override
  String toString() => 'Widget';
}

typedef Callback = void Function(Engine engine);

int top(int a, [int b = 1]) => a + b;
