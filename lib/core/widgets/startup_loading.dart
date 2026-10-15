import 'dart:async';

import 'package:flutter/material.dart';

import 'brand_mark.dart';

enum StartupStage { device, access, graphics, settings }

/// Plain painting keeps the first frame independent of optional glass shaders.
/// Stage labels describe real pending work; the progress has no fake percentage.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({required this.stage, super.key});

  final StartupStage stage;

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen> {
  Timer? _accessWait;
  bool _slowAccess = false;

  @override
  void initState() {
    super.initState();
    _watchStage();
  }

  @override
  void didUpdateWidget(StartupLoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) _watchStage();
  }

  void _watchStage() {
    _accessWait?.cancel();
    _slowAccess = false;
    if (widget.stage == StartupStage.access) {
      _accessWait = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _slowAccess = true);
      });
    }
  }

  @override
  void dispose() {
    _accessWait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final label = switch (widget.stage) {
      StartupStage.device =>
        persian ? 'آماده‌سازی دستگاه…' : 'Preparing device…',
      StartupStage.access => persian ? 'بررسی دسترسی…' : 'Checking access…',
      StartupStage.graphics =>
        persian ? 'آماده‌سازی رابط کاربری…' : 'Preparing interface…',
      StartupStage.settings =>
        persian ? 'بارگذاری تنظیمات…' : 'Loading settings…',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 64),
                  const SizedBox(height: 16),
                  Text('niraN', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(label, textAlign: TextAlign.center),
                  ),
                  if (_slowAccess) ...[
                    const SizedBox(height: 10),
                    Text(
                      persian
                          ? 'منتظر بررسی دسترسی هستیم. اتصال اینترنت را حفظ کنید.'
                          : 'Waiting for the access check. Please stay connected.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
