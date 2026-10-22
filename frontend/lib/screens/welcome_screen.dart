import 'package:flutter/material.dart';

import '../ui/ir_brand.dart';
import '../ui/ir_components.dart';
import '../ui/ir_motion.dart';
import '../ui/ir_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance =
      AnimationController(vsync: this, duration: IrMotion.entrance);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else if (!_started) {
      _entrance.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IrEditorialBackdrop(
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final compact = constraints.maxHeight < 660;
              final horizontal = wide ? 48.0 : 24.0;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: SingleChildScrollView(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 24, horizontal, 18),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 42)
                            .clamp(0, double.infinity),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (wide)
                            Row(
                              children: [
                                Expanded(child: _hero(compact)),
                                const SizedBox(width: 72),
                                SizedBox(width: 380, child: _actions(compact)),
                              ],
                            )
                          else ...[
                            _hero(compact),
                            SizedBox(height: compact ? 28 : 38),
                            _actions(compact),
                          ],
                          const SizedBox(height: 24),
                          const IrRouteTicker(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );

  Widget _hero(bool compact) => IrEntrance(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const IrBrandLogo(size: 44),
              const Spacer(),
              Container(width: 40, height: 2, color: context.irColors.accent),
              const SizedBox(width: 10),
              Text('CARTAGENA',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                      color: context.irColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.7)),
            ]),
            SizedBox(height: compact ? 30 : 52),
            Text(
              'Viaja para ganar',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.irColors.text,
                fontSize: compact ? 46 : 58,
                height: .94,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? -1.8 : -2.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(
                      color: context.irColors.accent,
                      borderRadius: BorderRadius.circular(99))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pide, acuerda y muévete por tu ciudad con claridad.',
                  style: TextStyle(
                    color: context.irColors.muted,
                    fontSize: 17,
                    height: 1.45,
                  ),
                ),
              ),
            ]),
          ],
        ),
      );

  Widget _actions(bool compact) => IrEntrance(
        delay: const Duration(milliseconds: 120),
        child: IrPanel(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) {
                  final value = Curves.easeOutCubic.transform(_entrance.value);
                  return Opacity(
                    opacity: .45 + (.55 * value),
                    child: Transform.scale(
                        scale: .86 + (.14 * value), child: child),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 16 : 26),
                  child: IrBrandLogo(size: compact ? 86 : 108),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context)
                    .push(_irOpeningRoute((_) => const RegisterScreen())),
                child: const Text('Crear cuenta'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .push(_irOpeningRoute((_) => const LoginScreen())),
                child: const Text('Iniciar sesión'),
              ),
            ],
          ),
        ),
      );

  PageRouteBuilder<void> _irOpeningRoute(WidgetBuilder pageBuilder) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PageRouteBuilder<void>(
      transitionDuration: reduceMotion
          ? const Duration(milliseconds: 140)
          : IrMotion.welcomeOpening,
      reverseTransitionDuration: reduceMotion
          ? const Duration(milliseconds: 120)
          : IrMotion.welcomeOpeningExit,
      pageBuilder: (context, _, __) => pageBuilder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }

        final content = animation.drive(CurveTween(
          curve: const Interval(.25, 1, curve: Curves.easeOutCubic),
        ));
        return Stack(
          fit: StackFit.expand,
          children: [
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .018),
                end: Offset.zero,
              ).animate(content),
              child: FadeTransition(opacity: content, child: child),
            ),
            Positioned.fill(
              child: _IrWelcomeReveal(animation: animation),
            ),
          ],
        );
      },
    );
  }
}

class _IrWelcomeReveal extends StatelessWidget {
  const _IrWelcomeReveal({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final progress = animation.value;
              final routeProgress = (progress / .48).clamp(0.0, 1.0).toDouble();
              final fadeProgress =
                  ((progress - .5) / .22).clamp(0.0, 1.0).toDouble();
              final opacity = 1 - Curves.easeInCubic.transform(fadeProgress);
              final logoProgress = (progress / .35).clamp(0.0, 1.0).toDouble();
              final scale =
                  .94 + (.06 * Curves.easeOutCubic.transform(logoProgress));

              return Opacity(
                opacity: opacity,
                child: Center(
                  child: SizedBox(
                    width: 220,
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(220, 180),
                          painter: _IrWelcomeRoutePainter(routeProgress),
                        ),
                        Transform.scale(
                          scale: scale,
                          child: const IrBrandLogo(size: 64),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _IrWelcomeRoutePainter extends CustomPainter {
  const _IrWelcomeRoutePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final route = Path()
      ..moveTo(size.width * .08, size.height * .84)
      ..cubicTo(
        size.width * .38,
        size.height * .84,
        size.width * .34,
        size.height * .2,
        size.width * .55,
        size.height * .5,
      )
      ..cubicTo(
        size.width * .75,
        size.height * .8,
        size.width * .74,
        size.height * .2,
        size.width * .94,
        size.height * .16,
      );
    final metrics = route.computeMetrics();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final distance = metric.length * progress;
    canvas.drawPath(
      metric.extractPath(0, distance),
      Paint()
        ..color = IrPalette.accent.withValues(alpha: .62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final endpoint = metric.getTangentForOffset(distance);
    if (endpoint != null && progress > 0) {
      canvas.drawCircle(
        endpoint.position,
        3,
        Paint()..color = IrPalette.accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IrWelcomeRoutePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
