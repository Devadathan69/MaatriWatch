import 'dart:math';
import 'package:flutter/material.dart';

/// Original vector illustrations: no remote stock images or copied app assets.
class FoodArt extends StatelessWidget {
  const FoodArt(
      {super.key, required this.kind, required this.label, this.size = 110});
  final String kind, label;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Illustration of $label',
      image: true,
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _FoodPainter(kind))));
}

class _FoodPainter extends CustomPainter {
  _FoodPainter(this.kind);
  final String kind;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    final p = Paint();
    void oval(Rect r, Color color) {
      p.color = color;
      canvas.drawOval(r, p);
    }

    void circle(double x, double y, double r, Color c) {
      p.color = c;
      canvas.drawCircle(Offset(x, y), r, p);
    }

    oval(const Rect.fromLTWH(12, 28, 98, 78), const Color(0xffE5CDB9));
    oval(const Rect.fromLTWH(8, 20, 104, 80), const Color(0xffFFFEF9));
    oval(const Rect.fromLTWH(19, 28, 82, 62), const Color(0xffF4E7D5));
    switch (kind) {
      case 'idli':
        for (final point in [
          const Offset(43, 49),
          const Offset(72, 46),
          const Offset(56, 71)
        ]) {
          oval(Rect.fromCenter(center: point, width: 33, height: 24),
              const Color(0xffD5CCBA));
          oval(
              Rect.fromCenter(
                  center: point.translate(0, -3), width: 32, height: 24),
              const Color(0xffFFFDF4));
        }
        circle(83, 73, 12, const Color(0xffB76B3C));
        circle(83, 73, 8, const Color(0xffDE9D55));
      case 'dosa':
        p.color = const Color(0xffD7A463);
        final path = Path()
          ..moveTo(25, 77)
          ..lineTo(83, 32)
          ..lineTo(88, 80)
          ..close();
        canvas.drawPath(path, p);
        p
          ..color = const Color(0xffB47F47)
          ..strokeWidth = 2;
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(
              Offset(40 + i * 8, 68 - i * 6), Offset(66 + i * 4, 78), p);
        }
        circle(33, 43, 12, const Color(0xffBE6755));
        circle(33, 43, 7, const Color(0xffD98B62));
      case 'fruit':
        circle(43, 58, 21, const Color(0xffE8AB5C));
        circle(71, 51, 19, const Color(0xffA6B782));
        oval(const Rect.fromLTWH(45, 66, 44, 16), const Color(0xffF2CE72));
        p.color = const Color(0xff64856A);
        canvas.drawOval(const Rect.fromLTWH(66, 26, 15, 8), p);
      case 'egg':
        oval(const Rect.fromLTWH(27, 38, 47, 39), const Color(0xffFFFEF7));
        circle(51, 57, 13, const Color(0xffE8B34C));
        for (var i = 0; i < 3; i++) {
          circle(83, 49 + i * 12, 9, const Color(0xff93AD87));
          circle(83, 49 + i * 12, 6, const Color(0xffC4D3A5));
        }
      case 'fish':
        p.color = const Color(0xffBF8A63);
        canvas.drawOval(const Rect.fromLTWH(28, 42, 54, 30), p);
        final tail = Path()
          ..moveTo(77, 57)
          ..lineTo(99, 40)
          ..lineTo(99, 76)
          ..close();
        canvas.drawPath(tail, p);
        circle(39, 53, 2, const Color(0xff5D493D));
        circle(32, 78, 9, const Color(0xff86A47C));
        circle(50, 81, 8, const Color(0xffA2B58A));
      case 'curd':
        oval(const Rect.fromLTWH(27, 35, 68, 48), const Color(0xffFFFEFA));
        for (final point in [
          const Offset(44, 52),
          const Offset(64, 61),
          const Offset(75, 46)
        ]) {
          circle(point.dx, point.dy, 5, const Color(0xff9A6D81));
        }
      default:
        final base = kind == 'rice'
            ? const Color(0xffE7CE9E)
            : kind == 'salad'
                ? const Color(0xff96AC7C)
                : kind == 'curry'
                    ? const Color(0xffD9AE64)
                    : const Color(0xffCDAE88);
        oval(const Rect.fromLTWH(24, 35, 72, 49), base);
        final rand = Random(kind.hashCode);
        for (var i = 0; i < 30; i++) {
          final a = rand.nextDouble() * pi * 2, r = rand.nextDouble() * 27;
          circle(
              60 + cos(a) * r,
              59 + sin(a) * r * .62,
              2 + rand.nextDouble() * 3,
              i % 3 == 0
                  ? const Color(0xffD69A63)
                  : i % 3 == 1
                      ? const Color(0xff71946C)
                      : const Color(0xffF3D9A1));
        }
    }
    p
      ..style = PaintingStyle.stroke
      ..color = const Color(0xffE8DBCD)
      ..strokeWidth = 1.5;
    canvas.drawOval(const Rect.fromLTWH(13, 24, 94, 70), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoodPainter oldDelegate) =>
      kind != oldDelegate.kind;
}
