import 'package:flutter/material.dart';

import 'ir_brand.dart';
import 'ir_motion.dart';
import 'ir_theme.dart';

class IrEditorialBackdrop extends StatelessWidget {
  const IrEditorialBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.irColors.surface),
          IgnorePointer(
            child: CustomPaint(
              painter: _IrBackdropPainter(
                color: context.irColors.text.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? .055
                      : .045,
                ),
                accent: context.irColors.accent.withValues(alpha: .16),
              ),
            ),
          ),
          child,
        ],
      );
}

class _IrBackdropPainter extends CustomPainter {
  const _IrBackdropPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = -step; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final route = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(size.width * .78, -20)
      ..cubicTo(size.width * .54, size.height * .2, size.width * 1.04,
          size.height * .42, size.width * .72, size.height * .68)
      ..cubicTo(size.width * .57, size.height * .8, size.width * .82,
          size.height * .92, size.width * .62, size.height + 20);
    canvas.drawPath(path, route);
    canvas.drawCircle(Offset(size.width * .72, size.height * .68), 5,
        Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _IrBackdropPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accent != accent;
}

class IrPageIntro extends StatelessWidget {
  const IrPageIntro({
    required this.title,
    required this.description,
    this.trailing,
    super.key,
  });

  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: context.irColors.accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.irColors.text,
                    fontSize: 30,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.15,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  description,
                  style: TextStyle(
                    color: context.irColors.muted,
                    fontSize: 15,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      );
}

class IrPanel extends StatelessWidget {
  const IrPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent = false,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.irColors;
    final panel = AnimatedContainer(
      duration: IrMotion.duration(context, IrMotion.transition),
      padding: padding,
      decoration: BoxDecoration(
        color: accent ? IrPalette.accent : colors.raised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent ? IrPalette.accent : colors.border,
        ),
      ),
      child: child,
    );
    if (onTap == null) return panel;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: panel,
      ),
    );
  }
}

class IrInfoRow extends StatelessWidget {
  const IrInfoRow({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => IrPanel(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.irColors.input,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: context.irColors.accent, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(description,
                      style: TextStyle(
                          color: context.irColors.muted, height: 1.4)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      );
}

class IrLoadingState extends StatelessWidget {
  const IrLoadingState({required this.label, this.compact = false, super.key});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              const IrLogoMark(size: 64),
              const SizedBox(height: 22),
            ],
            if (compact)
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: context.irColors.accent,
                ),
              )
            else
              SizedBox(
                width: 156,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: context.irColors.accent,
                    backgroundColor: context.irColors.border,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.irColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class IrButtonProgress extends StatelessWidget {
  const IrButtonProgress({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.irColors.muted,
        ),
      );
}

class IrEntrance extends StatefulWidget {
  const IrEntrance(
      {required this.child, this.delay = Duration.zero, super.key});

  final Widget child;
  final Duration delay;

  @override
  State<IrEntrance> createState() => _IrEntranceState();
}

class _IrEntranceState extends State<IrEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: IrMotion.entrance + widget.delay,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final total = IrMotion.entrance + widget.delay;
    final start = total.inMilliseconds == 0
        ? 0.0
        : (widget.delay.inMilliseconds / total.inMilliseconds).clamp(0.0, .8);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final raw = ((_controller.value - start) / (1 - start)).clamp(0.0, 1.0);
        final value = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: Transform.scale(
              alignment: Alignment.bottomCenter,
              scale: .96 + (.04 * value),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class IrRouteTicker extends StatefulWidget {
  const IrRouteTicker({super.key});

  @override
  State<IrRouteTicker> createState() => _IrRouteTickerState();
}

class _IrRouteTickerState extends State<IrRouteTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const text = 'CARTAGENA   RUTAS CLARAS   TARIFAS ACORDADAS   IR   ';
    return ClipRect(
      child: SizedBox(
        height: 34,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => FractionalTranslation(
            translation: Offset(-_controller.value * .5, 0),
            child: child,
          ),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Text(
              '$text$text',
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: context.irColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
