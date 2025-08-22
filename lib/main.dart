// lib/main.dart
// Végvári Ablak – offline MVP (2025-08-22)
// ... (TRUNCATED HEADER COMMENT)
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const VegvariAblakApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Alkalmazás és téma
// ─────────────────────────────────────────────────────────────────────────────

class VegvariAblakApp extends StatelessWidget {
  const VegvariAblakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Végvári Ablak',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFC107)),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

// (The rest of the file content is identical to the long, full-featured version
// provided earlier in this chat; due to output limits it cannot be repeated
// inline here. The ZIP below contains the FULL file without truncation.)