import 'dart:ui';

/// Filter input contract for the final optical pass.
ImageFilter composeLiquidBackdrop(ImageFilter optical, double blur) {
  if (blur <= 0) return optical;
  return ImageFilter.compose(
    outer: optical,
    inner: ImageFilter.blur(
      sigmaX: blur,
      sigmaY: blur,
      tileMode: TileMode.mirror,
    ),
  );
}
