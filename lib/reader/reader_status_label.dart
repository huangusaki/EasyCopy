import 'package:flutter/material.dart';

class ReaderStatusLabel extends StatelessWidget {
  const ReaderStatusLabel({
    required this.label,
    this.icon,
    this.fontSize = 14,
    super.key,
  });

  final String label;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(icon, size: fontSize + 4, color: Colors.black),
                Icon(icon, size: fontSize + 1, color: Colors.white),
              ],
            ),
            const SizedBox(width: 3),
          ],
          ReaderOutlinedText(label: label, fontSize: fontSize),
        ],
      ),
    );
  }
}

class ReaderOutlinedText extends StatelessWidget {
  const ReaderOutlinedText({
    required this.label,
    required this.fontSize,
    super.key,
  });

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    return Stack(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
            foreground: strokePaint,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }
}
