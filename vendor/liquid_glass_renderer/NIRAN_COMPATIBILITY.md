# Windows shader compatibility

Upstream: liquid_glass_renderer 0.2.0-dev.4, MIT license preserved.

Flutter 3.47's Windows build compiles all registered shaders for SkSL and
Impeller targets. Passing a uniform array by value generated array initializers
rejected by SkSL; non-constant loop bounds also prevented that target compiling.
MSBuild classified the reported compiler diagnostics as errors even when the
Impeller retry succeeded.

The local changes read the same uniform array directly, preserve its explicit
locations/declaration order and all optical math, use a fixed maximum loop with
an equivalent early break, and declare the existing sample radius constant.
Geometry normals use central SDF differences (half-pixel offsets) instead of
unsupported SkSL derivatives; the original normalized refraction calculation
and all blur, lighting and color settings remain intact. Only the two shaders
used by niraN's own-layer/blended path are registered; the unused legacy filter
and arbitrary/glassify alternatives are not bundled for this Windows fork.
The package cache and Flutter SDK are not patched.

For shapes with foreground content (niraN uses glassContainsChild=false), the
Gaussian blur is composed directly as the optical shader's input. This avoids
relying on two sibling backdrop captures to preserve the intermediate blurred
pixels on Windows GLES. The sigma and optical settings are not increased, and
the old separate blur pass is skipped so frost is applied exactly once.
Shapes whose children are intentionally refracted retain the upstream path.
The earlier panel-local-coordinate hypothesis was falsified by an isolated
Windows GPU probe. Flutter 3.47 preserves origin padding when rasterizing the
composed input. Background UVs use FlutterFragCoord/uSize, with no additional
origin subtraction. Geometry UVs still subtract the geometry origin.
On Windows, both background and geometry textures have top-left orientation:
the extra GLES Y flips caused the black body and inverted refraction near the
edges. Float uniform 18 selects this Windows foreground-only convention;
other platforms and refracted-child paths retain their upstream orientation.
The optical settings and lighting/refraction calculations are unchanged.
tool/verify_live_glass.dart is a GPU-only regression entrypoint, never a release
entrypoint. Its eight pixel samples fail on the old shader (RGB 6/6/6) and must
retain blue transmission at both translated surfaces and their top/bottom edges.
Flutter 3.47 includes the engine fix for blur/runtime-filter composition
(flutter/flutter#177687); the earlier 3.32 workaround is no longer required.
