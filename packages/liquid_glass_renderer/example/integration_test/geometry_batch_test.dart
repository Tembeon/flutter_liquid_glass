import 'package:integration_test/integration_test.dart';

import '../../test/src/atlas_page_reuse_test.dart' as reuse;
import '../../test/src/geometry_submit_batching_test.dart' as batching;

/// Runs the deferred-submission and texture-reuse checks on a device. Run in
/// debug mode so the submission counters are live.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  batching.runGeometrySubmitBatchingTests();
  reuse.runAtlasPageReuseTests();
}
