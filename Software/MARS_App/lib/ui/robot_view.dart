/// The robot, drawn live (CustomPainter, no 3D library):
///   left  - the lever dial: theta1 from hanging down (0) to horizontal (90) and up, the
///           WINDOW band, the target
///   right - the arm in the robot's plane: the links from the encoders (theta2..theta4),
///           with the start pose (everything hanging down) dashed. Kinematics as
///           the MARS desktop GUI's kinematics.py: x' down, z' along the motor axis.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../devices/mars/mars_device.dart';
import '../devices/mars/mars_protocol.dart';
import 'plots.dart' show dashedPath;
import 'theme.dart' as th;

class RobotView extends StatelessWidget {
  const RobotView({super.key, required this.device, required this.tick});

  final MarsDevice device;
  final Listenable tick;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: RepaintBoundary(child: CustomPaint(painter: _DialPainter(device, tick), size: Size.infinite))),
        const SizedBox(width: 10),
        Expanded(child: RepaintBoundary(child: CustomPaint(painter: _ArmPainter(device, tick), size: Size.infinite))),
      ]);
}

double _rad(double d) => d * math.pi / 180;

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..strokeWidth = w
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

void _text(Canvas canvas, String s, Offset at, {Color color = th.textFaint, double size = 11, bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontFamily: th.mono)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at - Offset(center ? tp.width / 2 : 0, tp.height / 2));
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.device, Listenable repaint) : super(repaint: repaint);
  final MarsDevice device;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width * 0.62, size.height * 0.46);
    if (r < 20) return;
    final o = Offset(size.width * 0.22, size.height * 0.48);
    // theta 0 = straight down, 90 = horizontal to the right (screen y is down)
    Offset dir(double deg) => Offset(math.sin(_rad(deg)), math.cos(_rad(deg)));
    Rect arc(double rr) => Rect.fromCircle(center: o, radius: rr);
    // canvas angles: 0 = +x, clockwise; theta maps to (90 - theta) degrees
    double ang(double deg) => _rad(90 - deg);

    final p = device.params;
    final lo = p['win_lo'] ?? 60, hi = p['win_hi'] ?? 120;
    canvas.drawArc(arc(r), ang(130), _rad(140), false, _stroke(th.border, 10));
    canvas.drawArc(arc(r), ang(hi), _rad(hi - lo), false, _stroke(th.accentDim.withValues(alpha: 0.55), 10));
    for (var d = 0; d <= 120; d += 30) {
      final a = o + dir(d.toDouble()) * (r + 9), b = o + dir(d.toDouble()) * (r + 16);
      canvas.drawLine(a, b, _stroke(th.plotAxis, 1.5));
      _text(canvas, '$d°', o + dir(d.toDouble()) * (r + 30), center: true);
    }
    _text(canvas, 'WINDOW', o + dir((lo + hi) / 2) * (r - 22), color: th.accentDim, size: 10, center: true);

    final s = device.latest;
    if (s == null || !device.live) {
      _text(canvas, 'θ1  --', o + Offset(0, r * 0.25), color: th.textFaint, size: 14);
      return;
    }
    if (s.on) {
      final t = o + dir(s.ref) * r;
      canvas.drawPath(dashedPath(Path()..moveTo(o.dx, o.dy)..lineTo(t.dx, t.dy), 6, 5), _stroke(th.gold, 2));
    }
    final tip = o + dir(s.theta) * r;
    canvas.drawLine(o, tip, _stroke(th.accent, 6));
    canvas.drawCircle(tip, 6, Paint()..color = th.accent);
    canvas.drawCircle(o, 8, Paint()..color = th.borderHi);
    canvas.drawCircle(o, 8, _stroke(th.accent, 2));
    _text(canvas, 'θ1 ${s.theta.toStringAsFixed(1)}°', o + Offset(-4, r * 0.35 + 14), color: th.text, size: 16);
  }

  @override
  bool shouldRepaint(_DialPainter old) => true;
}

class _ArmPainter extends CustomPainter {
  _ArmPainter(this.device, Listenable repaint) : super(repaint: repaint);
  final MarsDevice device;

  // In-plane points (x' down, z' along the motor axis), mm
  static List<Offset> _points(double t2, double t3) {
    final a2 = _rad(t2), a23 = _rad(t2 + t3);
    const p2 = Offset(j2X, j2Z);
    final p3 = p2 + Offset(math.cos(a2), math.sin(a2)) * r1;
    final p4 = p3 + Offset(math.cos(a23), math.sin(a23)) * r2;
    return [Offset.zero, p2, p3, p4];
  }

  @override
  void paint(Canvas canvas, Size size) {
    // fixed view: z' -500..900 across, x' -150..850 down
    const zLo = -500.0, zHi = 900.0, xLo = -150.0, xHi = 850.0;
    final scale = math.min(size.width / (zHi - zLo), size.height / (xHi - xLo));
    if (scale <= 0) return;
    final off = Offset((size.width - (zHi - zLo) * scale) / 2, (size.height - (xHi - xLo) * scale) / 2);
    Offset at(Offset p) => off + Offset((p.dy - zLo) * scale, (p.dx - xLo) * scale);

    // the motor axis and the start pose
    canvas.drawLine(at(const Offset(0, -450)), at(const Offset(0, 850)), _stroke(th.plotGrid, 1));
    _text(canvas, 'motor axis', at(const Offset(-40, 640)), size: 10);
    final zero = _points(0, 0);
    final zp = Path()..moveTo(at(zero[1]).dx, at(zero[1]).dy);
    for (final q in zero.skip(2)) {
      zp.lineTo(at(q).dx, at(q).dy);
    }
    canvas.drawPath(dashedPath(zp, 6, 6), _stroke(th.borderHi, 2));

    canvas.drawCircle(at(Offset.zero), 7, Paint()..color = th.borderHi);
    final s = device.latest;
    if (s == null || !device.live) {
      _text(canvas, 'no encoder data', at(const Offset(420, 200)), center: true);
      return;
    }
    final j = s.joints;
    final ok = s.encLinked && s.encOk(0) && s.encOk(1);
    final pts = _points(j[0], j[1]);
    final color = ok ? th.accent : th.textFaint;
    canvas.drawLine(at(pts[0]), at(pts[1]), _stroke(th.accentDim, 6));
    canvas.drawLine(at(pts[1]), at(pts[2]), _stroke(color, 6));
    canvas.drawLine(at(pts[2]), at(pts[3]), _stroke(color, 5));
    for (var i = 1; i < 3; i++) {
      final warn = s.encWarn(i - 1);
      canvas.drawCircle(at(pts[i]), 7, Paint()..color = th.bg);
      canvas.drawCircle(at(pts[i]), 7, _stroke(!s.encOk(i - 1) ? th.err : warn ? th.gold : th.ok, 2.5));
    }
    // cuff: a short bar across the forearm direction (theta4)
    final ca = _rad(j[0] + j[1] + j[2] + 90);
    final cdir = Offset(math.cos(ca), math.sin(ca)) * 70;
    canvas.drawLine(at(pts[3] - cdir), at(pts[3] + cdir), _stroke(s.encOk(2) ? th.gold : th.textFaint, 5));
    _text(canvas, 'θ2 ${j[0].toStringAsFixed(0)}°  θ3 ${j[1].toStringAsFixed(0)}°  θ4 ${j[2].toStringAsFixed(0)}°',
        Offset(8, size.height - 10), color: ok ? th.text : th.textFaint, size: 12);
  }

  @override
  bool shouldRepaint(_ArmPainter old) => true;
}
