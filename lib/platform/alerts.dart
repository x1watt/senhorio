// The permanent "you owe" notification on Android (MainActivity.showAlert).
// No-op elsewhere: the in-app banner (ui/widgets/alerts.dart) does the job.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AlertNotification {
  static const _ch = MethodChannel('com.x1watt.senhorio/bg');

  static bool get supported => !kIsWeb && Platform.isAndroid;
  static String? _last;

  /// Shows (or updates) the ongoing notification; [text] empty clears it.
  static Future<void> set(String title, String text) async {
    if (!supported) return;
    final key = '$title\n$text';
    if (key == _last) return;
    _last = key;
    try {
      if (text.isEmpty) {
        await _ch.invokeMethod('clearAlert');
      } else {
        await _ch.invokeMethod('requestNotifications');
        await _ch.invokeMethod('showAlert', {'title': title, 'text': text});
      }
    } on MissingPluginException {
      // tests
    }
  }
}
