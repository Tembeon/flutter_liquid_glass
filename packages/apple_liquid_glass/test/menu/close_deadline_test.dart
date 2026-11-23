import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);

MenuMotion _motion() => MenuMotion(
  source: MenuSource(_button),
  bounds: const Size(402, 874),
  itemCount: 3,
);

void main() {
  test('the morph asks for every vsync of a fast display', () {
    expect(_motion().needsFullFrameRate, isTrue);
  });

  test('explicit close is a command at its own time', () {
    final motion = _motion();
    motion.open(0);
    motion.advance(1);
    motion.close(1.1);
    expect(motion.now, 1.1);
    expect(motion.isClosing, isTrue);
    motion.advance(3);
    expect(motion.isPresented, isFalse);
  });
}
