/// Live plots, drawn with CustomPainter so they repaint at 20 Hz without rebuilding widgets.
/// TimePlot is DYNABO's; CopPlot shows the MARS load-cell platform.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/line_device.dart' show hostTime;
import '../devices/mars/mars_model.dart';
import '../devices/mars/mars_protocol.dart' show bHalfMm, lHalfMm;
import 'theme.dart' as th;
import 'widgets.dart';

class PlotSeries {
  const PlotSeries(this.key, this.label, this.color, {this.dashed = false});
  final String key;
  final String label;
  final Color color;
  final bool dashed;
}

/// Y range that fits the data, never tighter than minSpan (so noise doesn't look like motion).
/// It only changes when the data leaves it or shrinks a lot, so the axis doesn't jitter.
class _YRange {
  double? lo, hi;

  void update(double dLo, double dHi, double minSpan) {
    if (!dLo.isFinite) {
      dLo = -minSpan / 2;
      dHi = minSpan / 2;
    }
    final mid = (dLo + dHi) / 2, span = math.max(dHi - dLo, minSpan);
    final curLo = lo, curHi = hi;
    if (curLo == null || curHi == null || dLo < curLo || dHi > curHi || span < 0.4 * (curHi - curLo)) {
      lo = mid - span * 0.6;
      hi = mid + span * 0.6;
    }
  }
}

/// Rolling time plot: x = seconds (0 = now). Legend chips in the header show the latest values.
class TimePlot extends StatefulWidget {
  const TimePlot({
    super.key,
    required this.title,
    required this.model,
    required this.series,
    required this.tick,
    this.trailing,
    this.online,
    this.unit = '°',
    this.windowS = 10,
    this.minSpan = 4,
  });

  final String title;
  final MarsModel model;
  final List<PlotSeries> series;
  final Listenable tick;
  final Widget? trailing;
  final bool? online;
  final String unit;
  final double windowS;
  final double minSpan;

  @override
  State<TimePlot> createState() => _TimePlotState();
}

class _TimePlotState extends State<TimePlot> {
  final _yr = _YRange();

  @override
  Widget build(BuildContext context) {
    return DCard(
      title: widget.title,
      trailing: widget.trailing,
      online: widget.online,
      expand: true,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListenableBuilder(
          listenable: widget.tick,
          builder: (context, _) => Wrap(spacing: 18, runSpacing: 2, children: [
            for (final s in widget.series) _chip(s, lastFinite(widget.model.series[s.key]!)),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TimePainter(widget.model, widget.series, widget.windowS, widget.minSpan, _yr, widget.tick),
              size: Size.infinite,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(PlotSeries s, double? v) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 18, height: 10, child: CustomPaint(painter: _LineKeyPainter(s.color, s.dashed))),
      const SizedBox(width: 6),
      Text(s.label, style: const TextStyle(color: th.textMuted, fontSize: 12)),
      const SizedBox(width: 6),
      Text(v == null ? '--' : '${_signed(v, 1)}${widget.unit}', style: th.valueStyle.copyWith(fontSize: 12)),
    ]);
  }
}

class _LineKeyPainter extends CustomPainter {
  _LineKeyPainter(this.color, this.dashed);
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final y = size.height / 2;
    if (dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width * 0.4, y), p);
      canvas.drawLine(Offset(size.width * 0.6, y), Offset(size.width, y), p);
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_LineKeyPainter old) => old.color != color || old.dashed != dashed;
}

class _TimePainter extends CustomPainter {
  _TimePainter(this.model, this.series, this.windowS, this.minSpan, this.yr, Listenable repaint)
      : super(repaint: repaint);

  final MarsModel model;
  final List<PlotSeries> series;
  final double windowS, minSpan;
  final _YRange yr;

  static const _left = 38.0, _bottom = 18.0, _top = 4.0, _right = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    if (rect.width <= 10 || rect.height <= 10) return;
    final now = hostTime();
    final t0 = now - windowS;
    final start = math.max(0, model.firstIndexAfter(t0 - 0.2) - 1);
    final n = model.t.length;

    var lo = double.infinity, hi = double.negativeInfinity;
    for (final s in series) {
      final r = model.series[s.key]!;
      for (var i = start; i < n; i++) {
        final v = r[i];
        if (v.isFinite) {
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
      }
    }
    yr.update(lo, hi, minSpan);
    final yLo = yr.lo!, yHi = yr.hi!;
    double px(double t) => rect.left + (t - t0) / windowS * rect.width;
    double py(double v) => rect.bottom - (v - yLo) / (yHi - yLo) * rect.height;

    final grid = Paint()
      ..color = th.plotGrid
      ..strokeWidth = 1;
    final step = _niceStep((yHi - yLo) / 4);
    for (var v = (yLo / step).ceil() * step; v <= yHi; v += step) {
      final y = py(v);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      _label(canvas, _tickText(v, step), Offset(rect.left - 5, y), align: Alignment.centerRight);
    }
    final axis = Paint()
      ..color = th.plotAxis
      ..strokeWidth = 1;
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, axis);
    canvas.drawLine(rect.bottomLeft, rect.topLeft, axis);
    for (var s = 0; s <= windowS; s += 2) {
      final x = rect.right - s / windowS * rect.width;
      canvas.drawLine(Offset(x, rect.bottom), Offset(x, rect.bottom + 3), axis);
      _label(canvas, s == 0 ? '0 s' : '-$s', Offset(x, rect.bottom + 4), align: Alignment.topCenter);
    }

    canvas.save();
    canvas.clipRect(rect.inflate(1));
    for (final s in series) {
      final r = model.series[s.key]!;
      final path = Path();
      var pen = false;
      for (var i = start; i < n; i++) {
        final v = r[i];
        if (!v.isFinite) {
          pen = false;
          continue;
        }
        final o = Offset(px(model.t[i]), py(v));
        if (pen) {
          path.lineTo(o.dx, o.dy);
        } else {
          path.moveTo(o.dx, o.dy);
          pen = true;
        }
      }
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(s.dashed ? dashedPath(path, 7, 5) : path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TimePainter old) => true;
}

/// The load-cell platform seen from above: the 4 cells, the plate and the COP with a trail.
/// LC1 front-left, LC2 front-right, LC3 back-left, LC4 back-right; x + right, y + front.
class CopPlot extends StatelessWidget {
  const CopPlot({super.key, required this.model, required this.tick});

  final MarsModel model;
  final Listenable tick;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _CopPainter(model, tick), size: Size.infinite),
      );
}

class _CopPainter extends CustomPainter {
  _CopPainter(this.model, Listenable repaint) : super(repaint: repaint);
  final MarsModel model;

  @override
  void paint(Canvas canvas, Size size) {
    final fullW = bHalfMm * 2.5, fullH = lHalfMm * 2.5;
    final scale = math.min(size.width / fullW, size.height / fullH);
    if (scale <= 0) return;
    final c = size.center(Offset.zero);
    Offset at(double x, double y) => Offset(c.dx + x * scale, c.dy - y * scale);

    final plate = Rect.fromPoints(at(-bHalfMm, lHalfMm), at(bHalfMm, -lHalfMm));
    canvas.drawRect(plate, Paint()..color = th.bg);
    canvas.drawRect(
        plate,
        Paint()
          ..color = th.accentDim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final grid = Paint()..color = th.plotGrid;
    canvas.drawLine(at(-bHalfMm, 0), at(bHalfMm, 0), grid);
    canvas.drawLine(at(0, -lHalfMm), at(0, lHalfMm), grid);
    final cell = Paint()..color = th.borderHi;
    for (final (x, y) in const [(-1.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)]) {
      canvas.drawCircle(at(x * bHalfMm, y * lHalfMm), 4.5, cell);
    }
    _label(canvas, 'FRONT', at(0, lHalfMm) - const Offset(0, 4), align: Alignment.bottomCenter);

    final trail = model.copTrail;
    if (trail.isEmpty || !model.device.loadsLive) {
      final tp = TextPainter(
        text: TextSpan(
            text: model.device.loadsLive ? 'no load' : 'no load-cell data',
            style: const TextStyle(color: th.textFaint, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    final path = Path();
    var first = true;
    for (final o in trail) {
      final q = at(o.dx, o.dy);
      if (first) {
        path.moveTo(q.dx, q.dy);
        first = false;
      } else {
        path.lineTo(q.dx, q.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = th.gold.withValues(alpha: 0.35)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
    final last = at(trail.last.dx, trail.last.dy);
    canvas.drawCircle(last, 7, Paint()..color = th.gold);
    canvas.drawCircle(
        last,
        7,
        Paint()
          ..color = th.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CopPainter old) => true;
}

Path dashedPath(Path source, double on, double off) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
      d += on + off;
    }
  }
  return out;
}

double _niceStep(double raw) {
  if (raw <= 0 || !raw.isFinite) return 1;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  return (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * mag;
}

String _tickText(double v, double step) {
  final dec = step >= 1 ? 0 : (-(math.log(step) / math.ln10).floor()).clamp(0, 3);
  final s = v.toStringAsFixed(dec);
  return s == '-0' ? '0' : s;
}

void _label(Canvas canvas, String s, Offset at, {required Alignment align}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: const TextStyle(color: th.textFaint, fontSize: 10)),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = align.x < 0 ? 0.0 : align.x > 0 ? -tp.width : -tp.width / 2;
  final dy = align.y < 0 ? 0.0 : align.y > 0 ? -tp.height : -tp.height / 2;
  tp.paint(canvas, at + Offset(dx, dy));
}

String _signed(double v, int dec) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(dec)}';
