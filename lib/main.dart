import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/localization/app_strings.dart';
import 'core/diagnostics.dart';
import 'core/platform/native_models.dart';
import 'core/platform/nirang_native.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'features/vpn/app_controller.dart';
import 'features/vpn/app_shell.dart';
import 'features/registration/registration_bootstrap.dart';
import 'core/widgets/windows_glass_shader_warmup.dart';
import 'core/widgets/live_liquid_glass.dart';

Future<void> main() async {
  PaintingBinding.shaderWarmUp = const WindowsGlassShaderWarmUp();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    unawaited(
      _recordFrameworkError(details.exceptionAsString(), details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_recordFrameworkError(error.toString(), stack));
    return true;
  };
  ErrorWidget.builder = (details) => Builder(
    builder: (context) => Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'niraN recovered from a UI error.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    ),
  );
  final startupClock = Stopwatch()..start();
  // Start asynchronous preparation without holding the first Flutter frame.
  // Registration runs concurrently; the product child still waits for both.
  final graphicsReady = prepareLiveGlass().then((prepared) {
    debugPrint(
      'niraN graphics ready at ${startupClock.elapsedMilliseconds}ms: '
      'shaderFilter=${ImageFilter.isShaderFilterSupported}, programsReady=$prepared',
    );
  });
  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      adaptiveQuality: false,
      child: NiranRegistrationBootstrap(
        graphicsReady: graphicsReady,
        child: const ProviderScope(child: NirangApp()),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('niraN first frame at ${startupClock.elapsedMilliseconds}ms');
  });
}

Future<void> _recordFrameworkError(String message, StackTrace? stack) async {
  final report =
      'feature=${NirangDiagnostics.currentFeature} '
      'route=${NirangDiagnostics.currentRoute}\n'
      '$message\n${stack ?? ''}';
  try {
    await NirangNative.recordFlutterError(
      report.length <= 2000 ? report : report.substring(0, 2000),
    );
  } catch (_) {
    // The native bridge may not be ready during the earliest startup phase.
  }
}

class NirangApp extends ConsumerWidget {
  const NirangApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(
      appControllerProvider.select((value) {
        final settings = value.asData?.value.settings ?? const NativeSettings();
        return (
          themeMode: settings.themeModeValue,
          language: settings.language,
          accent: settings.accentColor,
          darkStyle: settings.darkStyle,
        );
      }),
    );
    return MaterialApp(
      navigatorKey: nirangNavigatorKey,
      navigatorObservers: [nirangRouteObserver],
      title: 'niraN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.personalized(
        Brightness.light,
        reducedEffects: false,
        accent: appearance.accent,
        darkStyle: appearance.darkStyle,
      ),
      darkTheme: AppTheme.personalized(
        Brightness.dark,
        reducedEffects: false,
        accent: appearance.accent,
        darkStyle: appearance.darkStyle,
      ),
      themeMode: appearance.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 120),
      themeAnimationCurve: Curves.easeOutCubic,
      scrollBehavior: const NirangScrollBehavior(reducedEffects: false),
      locale: Locale(appearance.language),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: MediaQuery.disableAnimationsOf(context),
          ),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: theme.colorScheme.surface,
              systemNavigationBarDividerColor: theme.colorScheme.outlineVariant,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarContrastEnforced: false,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AppShell(),
    );
  }
}
