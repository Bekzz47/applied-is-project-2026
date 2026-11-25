import 'package:flutter/material.dart';

const pine = Color(0xFF173D34);
const lime = Color(0xFFD3EF81);
const canvas = Color(0xFFF7F7F1);

String formatNumber(num number) {
  final parts = number.toStringAsFixed(number % 1 == 0 ? 0 : 2).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return parts.length == 1 ? whole : '$whole,${parts.last}';
}

class WarehouseMark extends StatelessWidget {
  const WarehouseMark({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: pine,
      borderRadius: BorderRadius.circular(size / 4),
    ),
    child: Icon(Icons.warehouse_outlined, color: lime, size: size * .70),
  );
}

class ErrorLine extends StatelessWidget {
  const ErrorLine({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
