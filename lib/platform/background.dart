// Android foreground service (SyncService.kt) that keeps the sync running
// with the app in the background. No-op elsewhere: desktop apps keep running.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundSync {
  static const _ch = MethodChannel('com.x1watt.senhorio/bg');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// [onTick] runs about once a minute while the service is up (native
  /// heartbeat: Dart timers are throttled in the background).
  static void init(Future<void> Function() onTick) {
    if (!supported) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onTick') await onTick();
      return null;
    });
  }

  static Future<void> start({required String title, required String text}) async {
    if (!supported) return;
    await _ch.invokeMethod('requestNotifications');
    await _ch.invokeMethod('start', {'title': title, 'text': text});
  }

  static Future<void> stop() async {
    if (!supported) return;
    await _ch.invokeMethod('stop');
  }

  static Future<bool> running() async =>
      supported && (await _ch.invokeMethod<bool>('running') ?? false);
}
