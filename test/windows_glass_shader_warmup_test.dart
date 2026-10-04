import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/windows_glass_shader_warmup.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:flutter/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('warmup covers the actual default glass kernel', () {
    const surface = GlassSurface(child: SizedBox());
    expect(WindowsGlassShaderWarmUp.filterSigmas, contains(surface.blur));
  });
  test('optional shader warm-up failure does not fail app startup', () async {
    await expectLater(const _FailingWarmUp().execute(), completes);
  });
}

class _FailingWarmUp extends WindowsGlassShaderWarmUp {
  const _FailingWarmUp();
  @override
  Future<void> warmUpOnCanvas(Canvas canvas) async {
    throw UnsupportedError('Synthetic unavailable render context');
  }
}
