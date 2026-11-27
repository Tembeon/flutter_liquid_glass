import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/widgets.dart';

void main() {
  test('it hears while attached and following, and catches up once with '
      'each callback when following turns on', () {
    final a = ValueNotifier(0);
    final b = ValueNotifier(0);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final heard = <String>[];
    void first() => heard.add('first');
    void second() => heard.add('second');
    final follow = MotionFollow.widget(
      following: false,
      heard: [(a, first), (b, first), (b, second)],
    );

    follow.attach();
    a.value = 1;
    expect(heard, isEmpty, reason: 'not following');

    follow.following = true;
    expect(heard, ['first', 'second'], reason: 'each callback once');
    heard.clear();

    a.value = 2;
    expect(heard, ['first']);
    heard.clear();

    follow.hear([(a, second)]);
    expect(heard, isEmpty, reason: 'a swap runs nothing');
    a.value = 3;
    b.value = 3;
    expect(heard, ['second']);
    heard.clear();

    follow.detach();
    a.value = 4;
    follow.attach();
    expect(heard, isEmpty, reason: 'nothing runs at attach');
    a.value = 5;
    expect(heard, ['second']);
    follow.detach();
  });
}
