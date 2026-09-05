import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController();
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    unawaited(_restore());
  }

  static const _key = 'passagetr.themeMode.v1';

  Future<void> _restore() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(_key);
      if (mounted && value != null) {
        state =
            value == ThemeMode.light.name ? ThemeMode.light : ThemeMode.dark;
      }
    } catch (_) {
      // Local storage can be unavailable in an isolated browser context.
    }
  }

  void setMode(ThemeMode mode) {
    if (mode == state) return;
    state = mode;
    unawaited(_save(mode));
  }

  void toggle() => setMode(
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );

  Future<void> _save(ThemeMode mode) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // A storage failure must not block the current-session preference.
    }
  }
}
