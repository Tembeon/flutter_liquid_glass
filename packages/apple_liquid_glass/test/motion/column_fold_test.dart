import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';

// A tab sidebar's forms: hidden, a rail 72 wide, a sidebar 200 to 400 that
// a hand left 280 wide.
const _forms = [
  ColumnForm(width: 0),
  ColumnForm(width: 72),
  ColumnForm(width: 280, min: 200, max: 400),
];

void main() {
  test('a hand moves the column within its form and sticks at its limits '
      'until it goes the fold distance past them', () {
    final fold = ColumnFold(_forms, form: 2, width: 280);
    expect(fold.update(60), isFalse);
    expect(fold.width, 340);
    fold.update(200);
    expect(fold.width, 400, reason: 'no wider form: it stops');
    fold.update(-100);
    expect((fold.form, fold.width), (2, 200));
    expect(fold.update(-129), isFalse);
    expect(fold.width, 200, reason: 'stuck short of the fold');
    expect(fold.update(-130), isTrue);
    expect((fold.form, fold.width), (1, 72));
  });

  test('one drag folds the sidebar into the rail and the rail away, and '
      'unfolds them at the widths they had', () {
    final fold = ColumnFold(_forms, form: 2, width: 280);
    fold.update(-130);
    expect(fold.form, 1);
    fold.update(-150);
    expect(fold.width, 72, reason: 'a rail keeps its width');
    fold.update(-180);
    expect((fold.form, fold.width), (0, 0));
    fold.update(-140);
    expect(fold.form, 0, reason: 'short of the fold distance back');
    fold.update(-130);
    expect((fold.form, fold.width), (1, 72));
    fold.update(-80);
    expect((fold.form, fold.width), (2, 280));
    fold.update(-60);
    expect(fold.width, 300, reason: 'the drag goes on from the fold');
  });

  test('a column of one form stops at its limits', () {
    final fold = ColumnFold(
      const [ColumnForm(width: 320, min: 240, max: 500)],
      form: 0,
      width: 320,
      position: 100,
    );
    fold.update(-300);
    expect((fold.form, fold.width), (0, 240));
  });

  test('a step folds from a limit and unfolds from a fixed form', () {
    expect(
      ColumnFold.step(_forms, form: 2, width: 250, by: -43),
      (2, 207),
    );
    expect(ColumnFold.step(_forms, form: 2, width: 207, by: -43), (2, 200));
    expect(ColumnFold.step(_forms, form: 2, width: 200, by: -43), (1, 72));
    expect(ColumnFold.step(_forms, form: 1, width: 72, by: -43), (0, 0));
    expect(ColumnFold.step(_forms, form: 0, width: 0, by: -43), (0, 0));
    expect(ColumnFold.step(_forms, form: 1, width: 72, by: 43), (2, 280));
    expect(ColumnFold.step(_forms, form: 2, width: 400, by: 43), (2, 400));
  });
}
