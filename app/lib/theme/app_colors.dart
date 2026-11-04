import 'package:flutter/material.dart';

/// Einzige Stelle mit Farbwerten. Alles andere nutzt diese Konstanten oder das Theme.
abstract final class AppColors {
  // ---------- Markenpalette ----------
  static const greige = Color(0xFFB5ACA3); // warm, neutral
  static const sky = Color(0xFFB0D2EC); // hell, Akzentflächen
  static const dusk = Color(0xFF849DBB); // Taubenblau
  static const blue = Color(0xFF648EC0); // Hauptakzent
  static const espresso = Color(0xFF533A33); // Text, Buttons, Logo-Grund

  // Abgeleitete Töne für Flächen und Text (gleiche Farbfamilie, nur heller/dunkler)
  static const blueDeep = Color(0xFF3F6A9E); // blau mit genug Kontrast für weiße Schrift
  static const linen = Color(0xFFF7F3EF); // Hintergrund hell
  static const sand = Color(0xFFEAE3DC); // Karten/Felder hell
  static const taupe = Color(0xFF7D7169); // gedämpfter Text hell
  static const roast = Color(0xFF1E1614); // Hintergrund dunkel
  static const cocoa = Color(0xFF2E2320); // Karten dunkel
  static const mocha = Color(0xFF41322D); // Felder dunkel

  // ---------- Trainingsarten ----------
  // Gedämpft wie die Palette, untereinander klar unterscheidbar, alle mit weißer Schrift lesbar (≥ 3:1).
  static const run = blueDeep; // Laufen = Markenblau
  static const strength = espresso; // Kraft = Espresso
  static const hyroxSim = Color(0xFFA9583F); // Terrakotta, warmes Gegenstück zum Blau
  static const mixed = Color(0xFF6E5E86); // Pflaume, liegt zwischen Blau und Braun
  static const recovery = Color(0xFF77784A); // Oliv, klar getrennt vom Erledigt-Grün
  static const rest = Color(0xFF8C8178); // Greige, abgedunkelt
  static const race = Color(0xFFA77A22); // Ocker/Gold für Renntage

  // ---------- Status ----------
  static const success = Color(0xFF3E7D5A); // erledigt
  static const warning = Color(0xFFC98A2E); // über Zielzeit, Rekorde
  static const danger = Color(0xFFB3412F); // langsamste Station, schlechter als zuvor
}
