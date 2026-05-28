import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and notifies theme mode changes.
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = saved == 'dark' ? ThemeMode.dark : saved == 'light' ? ThemeMode.light : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
  }
}

/// Minimal, clean design system for Stockz.
class AppColors {
  static const bg = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const text = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const textFaint = Color(0xFF94A3B8);
  static const up = Color(0xFF16A34A);
  static const down = Color(0xFFDC2626);
  static const accent = Color(0xFF0F172A);
}

const _tabular = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
);

ThemeData buildAppTheme() {
  const base = TextStyle(color: AppColors.text);

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      surface: AppColors.surface,
      onPrimary: Colors.white,
      onSurface: AppColors.text,
      error: AppColors.down,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: AppColors.text),
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.textMuted),
      labelLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
    ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: AppColors.text),
      shape: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textFaint),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textFaint,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: TextStyle(fontSize: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bg,
      side: const BorderSide(color: AppColors.border),
      labelStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMuted,
    ),
  );
}

class DarkColors {
  static const bg = Color(0xFF0A0A0A);       // near-black background
  static const surface = Color(0xFF1A1A1A);  // dark grey cards
  static const border = Color(0xFF2E2E2E);   // subtle border
  static const text = Color(0xFFFFFFFF);     // pure white text
  static const textMuted = Color(0xFFB0B0B0); // light grey secondary text
  static const textFaint = Color(0xFF666666); // faint hints/placeholders
  static const up = Color(0xFF22C55E);
  static const down = Color(0xFFEF4444);
  static const accent = Color(0xFF60A5FA);   // soft blue accent
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DarkColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: DarkColors.accent,
      surface: DarkColors.surface,
      onPrimary: DarkColors.bg,
      onSurface: DarkColors.text,
      error: DarkColors.down,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: DarkColors.text, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: DarkColors.text, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: DarkColors.text, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: DarkColors.text, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: DarkColors.text),
      bodyMedium: TextStyle(color: DarkColors.text),
      bodySmall: TextStyle(color: DarkColors.textMuted),
      labelLarge: TextStyle(color: DarkColors.text, fontWeight: FontWeight.w600),
    ).apply(bodyColor: DarkColors.text, displayColor: DarkColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: DarkColors.surface,
      foregroundColor: DarkColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: DarkColors.text, fontSize: 20, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: DarkColors.text),
      shape: Border(bottom: BorderSide(color: DarkColors.border, width: 1)),
    ),
    cardTheme: CardThemeData(
      color: DarkColors.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DarkColors.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DarkColors.accent,
        foregroundColor: DarkColors.bg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: DarkColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DarkColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DarkColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DarkColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DarkColors.accent, width: 1.5)),
      labelStyle: const TextStyle(color: DarkColors.textMuted),
      hintStyle: const TextStyle(color: DarkColors.textFaint),
    ),
    dividerTheme: const DividerThemeData(color: DarkColors.border, thickness: 1, space: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: DarkColors.surface,
      selectedItemColor: DarkColors.accent,
      unselectedItemColor: DarkColors.textFaint,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: TextStyle(fontSize: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DarkColors.bg,
      side: const BorderSide(color: DarkColors.border),
      labelStyle: const TextStyle(color: DarkColors.text, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: DarkColors.textMuted),
  );
}

/// Tabular numerals — use for prices, percentages, anything aligned in lists.
TextStyle tabular(TextStyle base) => base.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Standard signal/prediction pill background.
class SignalPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool subtle;

  const SignalPill({super.key, required this.label, required this.color, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: subtle ? color.withOpacity(0.1) : color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: subtle ? color : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Empty state with icon + heading + subtext.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurface.withOpacity(0.35)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
