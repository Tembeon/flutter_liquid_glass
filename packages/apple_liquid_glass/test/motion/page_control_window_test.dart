import 'package:apple_liquid_glass/src/motions/page_control_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('more pages than 8 show through a window of 8 slots, its slots next '
      'to pages beyond it smaller, as the iOS 27.2 simulator lays out 12', () {
    final motion = PageControlMotion(count: 12, page: 0);
    expect(motion.size.width, moreOrLessEquals(161.33, epsilon: 0.05));
    expect(
      PageControlMotion.sizeFor(12).width,
      moreOrLessEquals(161.33, epsilon: 0.05),
    );
    List<double> scales() => [for (var i = 0; i < 12; i++) motion.scaleOf(i)];
    const near = PageControlTuning.windowNearScale;
    const far = PageControlTuning.windowFarScale;
    expect(scales(), [1, 1, 1, 1, 1, 1, near, far, 0, 0, 0, 0]);
    motion.setPage(0, 5);
    expect(scales(), [1, 1, 1, 1, 1, 1, near, far, 0, 0, 0, 0]);
    motion.setPage(0, 6);
    expect(scales(), [0, far, near, 1, 1, 1, 1, near, far, 0, 0, 0]);
    motion.setPage(0, 9);
    expect(scales(), [0, 0, 0, 0, far, near, 1, 1, 1, 1, 1, 1]);
    final rects = motion.indicatorRects(rtl: false);
    expect(rects[4].center.dx, moreOrLessEquals(19, epsilon: 0.2));
    expect(rects[11].center.dx, moreOrLessEquals(142.67, epsilon: 0.2));
    motion.setPage(0, 7);
    expect(scales(), [0, 0, 0, 0, far, near, 1, 1, 1, 1, 1, 1]);
  });

  test('a control of 12 pages set to page 9 opens on the window that ends '
      'at the last page', () {
    final motion = PageControlMotion(count: 12, page: 9);
    expect(motion.scaleOf(4), PageControlTuning.windowFarScale);
    expect(motion.scaleOf(11), 1);
    expect(motion.scaleOf(3), 0);
  });
}
