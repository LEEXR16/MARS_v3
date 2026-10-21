/// The Mars theme: the same colours as the desktop MARS GUI (the MARS desktop GUI's theme.py), with
/// DYNABO's token names so the shared widgets work unchanged.
library;

import 'package:flutter/material.dart';

// ---- Surfaces ----
const bg = Color(0xFF0A0705); // window
const panel = Color(0xFF110C08); // header, dialogs
const card = Color(0xFF16100B); // panels
const cardHi = Color(0xFF21180F); // inputs, outlined buttons
const border = Color(0xFF2B1F14);
const borderHi = Color(0xFF3D2C1D);

// ---- Text ----
const text = Color(0xFFF5E9D8);
const textMuted = Color(0xFFAD9478);
const textFaint = Color(0xFF6E5A45);

// ---- Accent and status ----
const accent = Color(0xFFF2A254); // desert amber: live values, main curves
const accentDim = Color(0xFF8C5D2E);
const gold = Color(0xFFFFDC8F); // pale sun gold: targets, alpha, toggles that are ON
const ok = Color(0xFF5FD38D);
const warn = Color(0xFFFFC56B);
const err = Color(0xFFFF4D5E); // faults only
const errStrong = Color(0xFFFF2E44);
const idle = Color(0xFF6E5A45);

// ---- Plots ----
const plotGrid = Color(0xFF22190F);
const plotAxis = Color(0xFF4A3826);

enum Level { ok, warn, error, idle, info, gold }

Color levelColor(Level l) => switch (l) {
      Level.ok => ok,
      Level.warn => warn,
      Level.error => err,
      Level.idle => idle,
      Level.info => accent,
      Level.gold => gold,
    };

const mono = 'monospace';
const titleFont = 'Oxanium';

const cardTitle = TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.4,
    fontFamily: titleFont);
const muted = TextStyle(color: textMuted, fontSize: 13);
const faint = TextStyle(color: textFaint, fontSize: 11);
const valueStyle = TextStyle(color: text, fontSize: 13, fontFamily: mono);

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF1A1007),
      secondary: gold,
      surface: card,
      onSurface: text,
      error: err,
    ),
    scaffoldBackgroundColor: bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    dividerColor: border,
    dialogTheme: const DialogThemeData(
      backgroundColor: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: borderHi),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: gold,
      inactiveTrackColor: border,
      thumbColor: text,
      disabledActiveTrackColor: borderHi,
      disabledInactiveTrackColor: border,
      disabledThumbColor: textFaint,
      overlayColor: Color(0x22FFDC8F),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF1A1007),
        disabledBackgroundColor: accent.withValues(alpha: 0.15),
        disabledForegroundColor: textFaint,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.6),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        backgroundColor: cardHi,
        disabledForegroundColor: textFaint,
        side: const BorderSide(color: borderHi),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textMuted,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: borderHi),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : bg),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: cardHi,
      contentTextStyle: TextStyle(color: text),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent, linearTrackColor: border),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: bg,
      border: OutlineInputBorder(borderSide: BorderSide(color: borderHi)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderHi)),
    ),
  );
}
