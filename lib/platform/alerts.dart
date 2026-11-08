// The permanent "you owe" notification and the "update ready" one on
// Android (MainActivity). No-op elsewhere: the in-app banners do the job.

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

/// "A new version is ready to install" on Android (MainActivity.showUpdate):
/// a normal notification, cleared once the update is installed.
class UpdateNotification {
  static const _ch = MethodChannel('com.x1watt.senhorio/bg');

  static Future<void> show(String title, String text) async {
    if (!AlertNotification.supported) return;
    try {
      await _ch.invokeMethod('requestNotifications');
      await _ch.invokeMethod('showUpdate', {'title': title, 'text': text});
    } on MissingPluginException {
      // tests
    }
  }

  static Future<void> clear() async {
    if (!AlertNotification.supported) return;
    try {
      await _ch.invokeMethod('clearUpdate');
    } on MissingPluginException {
      // tests
    }
  }
}
