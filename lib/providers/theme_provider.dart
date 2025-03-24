import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  static const String _kThemePreferenceKey = 'isDarkMode';

  ThemeProvider() {
    _loadThemePreference();
  }

  bool get isDarkMode => _isDarkMode;

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_kThemePreferenceKey) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Ошибка при загрузке настроек темы: $e');
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kThemePreferenceKey, _isDarkMode);
    } catch (e) {
      debugPrint('Ошибка при сохранении настроек темы: $e');
    }
  }
} 