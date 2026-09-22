import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/windows_release_state.dart';

void main() {
  test('fresh install does not show What\'s New', () async {
    final directory = await Directory.systemTemp.createTemp('niran-release-');
    addTearDown(() => directory.delete(recursive: true));
    final state = WindowsReleaseState(directory: directory);
    expect(await state.shouldShowWhatsNew('0.3.6'), isFalse);
  });

  test('upgrade shows once and acknowledgement persists', () async {
    final directory = await Directory.systemTemp.createTemp('niran-release-');
    addTearDown(() => directory.delete(recursive: true));
    final state = WindowsReleaseState(directory: directory);
    await state.shouldShowWhatsNew('0.3.5');
    expect(await state.shouldShowWhatsNew('0.3.6'), isTrue);
    await state.markSeen('0.3.6');
    expect(await state.shouldShowWhatsNew('0.3.6'), isFalse);
  });

  test('replacement build of the same release shows once', () async {
    final directory = await Directory.systemTemp.createTemp('niran-release-');
    addTearDown(() => directory.delete(recursive: true));
    final state = WindowsReleaseState(directory: directory);
    await state.shouldShowWhatsNew('0.3.6+9');
    expect(await state.shouldShowWhatsNew('0.3.6+10'), isTrue);
    await state.markSeen('0.3.6+10');
    expect(await state.shouldShowWhatsNew('0.3.6+10'), isFalse);
  });

  test('0.3.6 QA upgrade to 0.3.7 shows once', () async {
    final directory = await Directory.systemTemp.createTemp('niran-release-');
    addTearDown(() => directory.delete(recursive: true));
    final state = WindowsReleaseState(directory: directory);
    await state.shouldShowWhatsNew('0.3.6+10');
    expect(await state.shouldShowWhatsNew('0.3.7+11'), isTrue);
    await state.markSeen('0.3.7+11');
    expect(await state.shouldShowWhatsNew('0.3.7+11'), isFalse);
  });
}
