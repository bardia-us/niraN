import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const primary = Color(0xFF625BD2);
  static const lightCanvas = Color(0xFFF8F8FC);
  static const darkCanvas = Color(0xFF10111A);
  static const lightSuccess = Color(0xFF287A62);
  static const darkSuccess = Color(0xFF6FC5AA);
  static const lightWarning = Color(0xFF9A6717);
  static const darkWarning = Color(0xFFE0B465);
}

@immutable
class NirangSemanticColors extends ThemeExtension<NirangSemanticColors> {
  const NirangSemanticColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  @override
  NirangSemanticColors copyWith({Color? success, Color? warning}) =>
      NirangSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
      );

  @override
  NirangSemanticColors lerp(covariant NirangSemanticColors? other, double t) =>
      other == null
      ? this
      : NirangSemanticColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

extension NirangThemeContext on BuildContext {
  NirangSemanticColors get semanticColors =>
      Theme.of(this).extension<NirangSemanticColors>()!;
}

abstract final class AppTheme {
  static const accentColors = <String, Color>{
    'purple': AppPalette.primary,
    'blue': Color(0xFF1976D2),
    'teal': Color(0xFF008B8B),
    'green': Color(0xFF328449),
    'orange': Color(0xFFB96B17),
    'rose': Color(0xFFB94F84),
  };
  static final _personalized = <String, ThemeData>{};
  static ThemeData personalized(
    Brightness brightness, {
    required bool reducedEffects,
    required String accent,
    required String darkStyle,
  }) => _personalized.putIfAbsent(
    '${brightness.name}:$reducedEffects:$accent:$darkStyle',
    () => _theme(
      brightness,
      reducedEffects,
      accent: accent,
      darkStyle: darkStyle,
    ),
  );
  static final ThemeData light = _theme(Brightness.light, false);
  static final ThemeData dark = _theme(Brightness.dark, false);
  static final ThemeData lightPerformance = _theme(Brightness.light, true);
  static final ThemeData darkPerformance = _theme(Brightness.dark, true);

  static ThemeData _theme(
    Brightness brightness,
    bool reducedEffects, {
    String accent = 'purple',
    String darkStyle = 'graphite',
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColors[accent] ?? AppPalette.primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? switch (darkStyle) {
              'graphite' => const Color(0xFF18191C),
              'oled' => Colors.black,
              _ => AppPalette.darkCanvas,
            }
          : AppPalette.lightCanvas,
      extensions: [
        NirangSemanticColors(
          success: isDark ? AppPalette.darkSuccess : AppPalette.lightSuccess,
          warning: isDark ? AppPalette.darkWarning : AppPalette.lightWarning,
        ),
      ],
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: reducedEffects
              ? const FadeUpwardsPageTransitionsBuilder()
              : const ZoomPageTransitionsBuilder(
                  allowEnterRouteSnapshotting: true,
                ),
        },
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .55),
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface.withValues(alpha: .78),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow.withValues(alpha: isDark ? .76 : .82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minVerticalPadding: 8,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: scheme.primary.withValues(alpha: isDark ? .24 : .13),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 25),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 23,
        ),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outline.withValues(alpha: .4)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 40),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size(40, 40),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 2,
        barrierColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerHigh.withValues(
          alpha: isDark ? .91 : .93,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 2,
        modalBackgroundColor: scheme.surfaceContainer.withValues(
          alpha: isDark ? .94 : .96,
        ),
        modalBarrierColor: Colors.transparent,
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}

abstract final class NirangVisualEffects {
  static BoxDecoration shellBackground(
    ThemeData theme, {
    required bool reducedEffects,
  }) {
    final background = theme.scaffoldBackgroundColor;
    if (reducedEffects) return BoxDecoration(color: background);

    final scheme = theme.colorScheme;
    if (theme.brightness == Brightness.dark) {
      return BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.72, -.82),
          radius: 1.45,
          colors: [
            Color.alphaBlend(scheme.primary.withValues(alpha: .12), background),
            Color.alphaBlend(
              scheme.secondary.withValues(alpha: .05),
              background,
            ),
            background,
          ],
          stops: const [0, .38, 1],
        ),
      );
    }

    // Keep every light-mode gradient stop opaque. Transparent gradient stops
    // can be composited as black by some Android GPU drivers when combined
    // with a backdrop filter.
    final primaryGlow = Color.alphaBlend(
      scheme.primary.withValues(alpha: .075),
      background,
    );
    final secondaryGlow = Color.alphaBlend(
      scheme.secondary.withValues(alpha: .028),
      background,
    );
    return BoxDecoration(
      color: background,
      gradient: RadialGradient(
        center: const Alignment(.78, -.94),
        radius: 1.55,
        colors: [primaryGlow, secondaryGlow, background],
        stops: const [0, .48, 1],
      ),
    );
  }

  static double chromeBlur(ThemeData theme, double darkValue) =>
      theme.brightness == Brightness.dark ? darkValue : 6;

  static Color chromeColor(
    ThemeData theme, {
    required bool reducedEffects,
    required double darkAlpha,
  }) {
    final alpha = reducedEffects
        ? .96
        : theme.brightness == Brightness.dark
        ? darkAlpha
        : .88;
    return theme.colorScheme.surface.withValues(alpha: alpha);
  }
}
