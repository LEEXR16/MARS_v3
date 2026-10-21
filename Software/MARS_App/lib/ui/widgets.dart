/// Small building blocks shared by every tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart' as th;

/// Rounded panel with an optional small uppercase title and a right-aligned header widget.
///
/// online: a green dot before the title while the component sends data; without data the dot
/// goes and the whole card fades. null = no online indicator.
/// expand: the child fills the card's height (plots); otherwise the card fits its content.
/// onTap: the whole card is tappable (plots: enlarge), shown by a small icon in the header.
class DCard extends StatelessWidget {
  const DCard(
      {super.key,
      this.title,
      this.trailing,
      this.online,
      required this.child,
      this.padding,
      this.expand = false,
      this.onTap});

  static const fadedOpacity = 0.32;

  final String? title;
  final Widget? trailing;
  final bool? online;
  final Widget child;
  final EdgeInsets? padding;
  final bool expand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || trailing != null || onTap != null;
    final body = Container(
      decoration: BoxDecoration(
        color: th.card,
        border: Border.all(color: th.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 22,
                child: Row(children: [
                  if (online == true) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: th.ok, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: title == null
                        ? const SizedBox()
                        : Text(title!.toUpperCase(), style: th.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  ?trailing,
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_full_rounded, size: 14, color: th.textFaint),
                  ],
                ]),
              ),
            ),
          if (expand) Expanded(child: child) else child,
        ],
      ),
    );
    final out = online == false ? Opacity(opacity: fadedOpacity, child: body) : body;
    if (onTap == null) return out;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: out);
  }
}

/// Small icon button for card headers (22 px high).
class SmallIconButton extends StatelessWidget {
  const SmallIconButton(this.icon, {super.key, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Icon(icon, size: 17, color: onPressed == null ? th.textFaint : th.textMuted),
          ),
        ),
      );
}

/// Rounded label with a coloured dot: connection, mode, errors...
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.level, {super.key});

  final String label;
  final th.Level level;

  @override
  Widget build(BuildContext context) {
    final c = th.levelColor(level);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: th.text), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// "Label ............ value unit" in a monospace value column.
class ValueRow extends StatelessWidget {
  const ValueRow(this.label, this.value, {super.key, this.unit = '', this.dot, this.valueColor});

  final String label;
  final String value;
  final String unit;
  final Color? dot;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        if (dot != null) ...[
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 7),
        ],
        Expanded(child: Text(label, style: th.muted, overflow: TextOverflow.ellipsis)),
        Text(value, style: th.valueStyle.copyWith(color: valueColor)),
        if (unit.isNotEmpty) SizedBox(width: 24, child: Text(' $unit', style: th.faint)),
      ]),
    );
  }
}

/// Label, hint and value on one line, slider underneath. Tap the value to type a number.
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.decimals = 1,
    this.suffix = '',
    this.hint = '',
    this.enabled = true,
  });

  final String label;
  final double min, max, value;
  final int decimals;
  final String suffix;
  final String hint;
  final bool enabled;
  final ValueChanged<double> onChanged;

  double _snap(double v) {
    final scale = _pow10(decimals);
    return (v.clamp(min, max) * scale).roundToDouble() / scale;
  }

  Future<void> _edit(BuildContext context) async {
    final ctl = TextEditingController(text: value.toStringAsFixed(decimals));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
          style: th.valueStyle.copyWith(fontSize: 18),
          decoration: InputDecoration(
            suffixText: suffix.trim(),
            helperText: '${min.toStringAsFixed(decimals)} … ${max.toStringAsFixed(decimals)}',
          ),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text.replaceAll(',', '.'))),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (v != null && v.isFinite) onChanged(_snap(v));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Flexible(child: Text(label, style: th.muted, overflow: TextOverflow.ellipsis)),
        const Spacer(),
        if (hint.isNotEmpty) Text(hint, style: th.faint),
        const SizedBox(width: 8),
        InkWell(
          onTap: enabled ? () => _edit(context) : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: th.bg,
              border: Border.all(color: th.borderHi),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${value.toStringAsFixed(decimals)}$suffix',
              textAlign: TextAlign.right,
              style: th.valueStyle.copyWith(color: enabled ? th.text : th.textFaint),
            ),
          ),
        ),
      ]),
      SizedBox(
        height: 36,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: enabled ? (v) => onChanged(_snap(v)) : null,
        ),
      ),
    ]);
  }
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.center = false});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: th.faint, textAlign: center ? TextAlign.center : TextAlign.start);
}

const hline = Divider(height: 1, thickness: 1, color: th.border);

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
