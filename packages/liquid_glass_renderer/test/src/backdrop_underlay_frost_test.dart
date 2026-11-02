import 'package:flutter_test/flutter_test.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets('frosted glass over its copy draws what reading the backdrop '
      'draws', (tester) async {
    expect(await underlayParity(tester, frost: 8), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);
}
