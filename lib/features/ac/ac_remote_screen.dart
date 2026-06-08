// features/ac/ac_remote_screen.dart
//
// AC Remote Control — KRA ON TeknoPoint Simulator
// Full LCD + Arc Gauge + Mode/Fan/Swing/Auto/Season/Power
// Same Glassmorphism · Neon · No setState

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homesync/core/services/gas_notification_service.dart';
import 'package:homesync/features/providers/mqtt_provider.dart';
import 'package:homesync/models/mqtt_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS (same as home_screen)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _DT {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const glass = Color(0x0DFFFFFF);
  static const border = Color(0x1AFFFFFF);
  static const neonGreen = Color(0xFF00FF88);
  static const neonRed = Color(0xFFFF2060);
  static const neonBlue = Color(0xFF00D4FF);
  static const neonPurple = Color(0xFFBF5FFF);
  static const neonYellow = Color(0xFFFFD000);
  static const neonOrange = Color(0xFFFF6B35);
  static const neonCyan = Color(0xFF00FFFF);
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const acCool = Color(0xFF00D4FF);
  static const acWarm = Color(0xFFFF6B00);
  static const radius = 16.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// AC REMOTE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AcRemoteScreen extends ConsumerWidget {
  const AcRemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mqttState = ref.watch(mqttNotifierProvider);
    final mqttNotifier = ref.read(mqttNotifierProvider.notifier);

    // ✅ Gas Alert listener
    ref.listen(mqttNotifierProvider, (previous, next) {
      if (previous?.gasLevel != next.gasLevel && next.gasLevel != 'OK') {
        GasNotificationService().showGasAlert(next.gasLevel);
      }
    });

    return Scaffold(
      backgroundColor: _DT.bg,
      extendBodyBehindAppBar: true,
      appBar: _CyberAppBar(
        isConnected: mqttState.isConnected,
        gasLevel: mqttState.gasLevel,
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label: 'AC STATUS'),
              const SizedBox(height: 8),
              _LcdScreen(state: mqttState),
              const SizedBox(height: 24),

              _SectionLabel(label: 'TEMPERATURE'),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1.8,
                child: _AcTempGauge(
                  temperature: mqttState.acTemp.toDouble(),
                  onTemperatureChanged: (t) => mqttNotifier.sendAcJson({
                    'cmd': 'set',
                    'temp': t.round().clamp(18, 29),
                  }),
                ),
              ),
              const SizedBox(height: 24),

              _SectionLabel(label: 'MODE'),
              const SizedBox(height: 8),
              _ModePanel(state: mqttState, notifier: mqttNotifier),
              const SizedBox(height: 24),

              _SectionLabel(label: 'FAN & SWING'),
              const SizedBox(height: 8),
              _FanSwingPanel(state: mqttState, notifier: mqttNotifier),
              const SizedBox(height: 24),

              _SectionLabel(label: 'SYSTEM'),
              const SizedBox(height: 8),
              _SystemPanel(state: mqttState, notifier: mqttNotifier),
              const SizedBox(height: 24),

              _SectionLabel(label: 'POWER'),
              const SizedBox(height: 8),
              _PowerButton(state: mqttState, notifier: mqttNotifier),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP BAR (with back button + GAS)
// ─────────────────────────────────────────────────────────────────────────────
class _CyberAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CyberAppBar({
    required this.isConnected,
    required this.gasLevel,
    required this.onBack,
  });
  final bool isConnected;
  final String gasLevel;
  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: _DT.textPrimary),
        onPressed: onBack,
      ),
      title: const Text(
        'AC CONTROL',
        style: TextStyle(
          color: _DT.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
        ),
      ),
      centerTitle: true,
      actions: [
        _GasAlertButton(gasLevel: gasLevel),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(isConnected: isConnected),
              const SizedBox(width: 6),
              Text(
                isConnected ? 'LIVE' : 'OFFLINE',
                style: TextStyle(
                  color: isConnected ? _DT.neonGreen : _DT.neonRed,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GAS ALERT BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _GasAlertButton extends StatelessWidget {
  const _GasAlertButton({required this.gasLevel});
  final String gasLevel;

  @override
  Widget build(BuildContext context) {
    final isAlert = gasLevel == 'ALERT';
    final isWarn = gasLevel == 'WARN';
    final color = isAlert
        ? _DT.neonRed
        : isWarn
        ? _DT.neonOrange
        : _DT.neonGreen;

    return GestureDetector(
      onTap: () => GasNotificationService().showGasAlert(gasLevel),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.1),
          border: Border.all(
            color: color.withValues(alpha: isAlert || isWarn ? 0.8 : 0.3),
            width: isAlert ? 2 : 1,
          ),
          boxShadow: isAlert
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(Icons.local_gas_station, color: color, size: 16),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING DOT
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.isConnected});
  final bool isConnected;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected ? _DT.neonGreen : _DT.neonRed;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.85),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: _DT.neonBlue,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: _DT.neonBlue.withValues(alpha: 0.6),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: _DT.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.glowColor,
    this.isAlert = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glowColor;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_DT.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(_DT.radius),
            border: Border.all(color: _DT.border),
            boxShadow: [
              if (isAlert)
                BoxShadow(
                  color: _DT.neonRed.withValues(alpha: 0.28),
                  blurRadius: 28,
                  spreadRadius: 2,
                )
              else if (glowColor != null)
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.12),
                  blurRadius: 20,
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LCD SCREEN (Black display with neon text)
// ─────────────────────────────────────────────────────────────────────────────
class _LcdScreen extends StatelessWidget {
  const _LcdScreen({required this.state});
  final MqttState state;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: state.acPower
                ? _DT.neonGreen.withValues(alpha: 0.4)
                : _DT.textSecondary.withValues(alpha: 0.2),
          ),
          boxShadow: state.acPower
              ? [
                  BoxShadow(
                    color: _DT.neonGreen.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            _LcdRow(
              label: 'POWER',
              value: state.acPower ? 'ON' : 'OFF',
              valueColor: state.acPower ? _DT.neonGreen : _DT.neonRed,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'MODE',
              value: state.acMode.toUpperCase(),
              valueColor: _DT.acCool,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'TEMP',
              value: '${state.acTemp}°C',
              valueColor: _DT.textPrimary,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'FAN',
              value: 'F${state.acFan}',
              valueColor: _DT.neonBlue,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'SWING',
              value: state.acSwing ? 'ON' : 'OFF',
              valueColor: state.acSwing ? _DT.neonGreen : _DT.neonRed,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'AUTO',
              value: state.acAutoMode ? 'ON' : 'OFF',
              valueColor: state.acAutoMode ? _DT.neonGreen : _DT.neonRed,
            ),
            const Divider(color: Colors.white10, height: 1),
            _LcdRow(
              label: 'SEASON',
              value: state.acSeason.toUpperCase(),
              valueColor: _DT.neonOrange,
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdRow extends StatelessWidget {
  const _LcdRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _DT.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              shadows: [
                Shadow(color: valueColor.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AC TEMPERATURE GAUGE (18-29°C)
// ─────────────────────────────────────────────────────────────────────────────
class _AcTempGauge extends StatefulWidget {
  const _AcTempGauge({required this.temperature, this.onTemperatureChanged});

  final double temperature;
  final void Function(double)? onTemperatureChanged;

  @override
  State<_AcTempGauge> createState() => _AcTempGaugeState();
}

class _AcTempGaugeState extends State<_AcTempGauge> {
  static const _minT = 18.0;
  static const _maxT = 29.0;
  static const _startAngle = math.pi * 0.75;
  static const _sweepFull = math.pi * 1.50;
  static const _endAngle = _startAngle + _sweepFull;

  late final ValueNotifier<double> _tempVN;
  late final ValueNotifier<bool> _dragVN;
  Timer? _debounce;

  double _normalize(double t) =>
      ((t - _minT) / (_maxT - _minT)).clamp(0.0, 1.0);

  double? _posToTemp(Offset localPos, Offset center) {
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    var angle = math.atan2(dy, dx);
    if (angle < 0) angle += 2 * math.pi;

    if (angle > math.pi * 0.25 && angle < math.pi * 0.75) return null;

    final adjusted = angle < _startAngle ? angle + 2 * math.pi : angle;
    final clamped = adjusted.clamp(_startAngle, _endAngle);
    final t = (clamped - _startAngle) / _sweepFull;
    return _minT + t * (_maxT - _minT);
  }

  @override
  void initState() {
    super.initState();
    _tempVN = ValueNotifier(widget.temperature);
    _dragVN = ValueNotifier(false);
  }

  @override
  void didUpdateWidget(_AcTempGauge old) {
    super.didUpdateWidget(old);
    if (!_dragVN.value && old.temperature != widget.temperature) {
      _tempVN.value = widget.temperature;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tempVN.dispose();
    _dragVN.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d, Offset center) {
    final t = _posToTemp(d.localPosition, center);
    if (t == null) return;
    _dragVN.value = true;
    _tempVN.value = t;
  }

  void _onPanUpdate(DragUpdateDetails d, Offset center) {
    final t = _posToTemp(d.localPosition, center);
    if (t == null) return;
    _tempVN.value = t;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      widget.onTemperatureChanged?.call(t);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    _dragVN.value = false;
    _debounce?.cancel();
    widget.onTemperatureChanged?.call(_tempVN.value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size.width / 2, size.height / 2);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _onPanStart(d, center),
          onPanUpdate: (d) => _onPanUpdate(d, center),
          onPanEnd: _onPanEnd,
          child: ValueListenableBuilder<bool>(
            valueListenable: _dragVN,
            builder: (_, isDragging, __) => ValueListenableBuilder<double>(
              valueListenable: _tempVN,
              builder: (_, temp, __) {
                final progress = _normalize(temp);
                final arcColor = Color.lerp(_DT.acCool, _DT.acWarm, progress)!;

                return Stack(
                  children: [
                    CustomPaint(
                      size: size,
                      painter: _ArcGaugePainter(
                        progress: progress,
                        isDragging: isDragging,
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            temp.toStringAsFixed(1),
                            style: TextStyle(
                              color: arcColor,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              shadows: [
                                Shadow(
                                  color: arcColor.withValues(alpha: 0.55),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '°C',
                            style: TextStyle(
                              color: _DT.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedOpacity(
                            opacity: isDragging ? 1.0 : 0.35,
                            duration: const Duration(milliseconds: 200),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDragging
                                      ? Icons.send_rounded
                                      : Icons.rotate_right,
                                  size: 10,
                                  color: isDragging
                                      ? arcColor
                                      : _DT.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isDragging
                                      ? 'SET: ${temp.round()}°C'
                                      : 'DRAG TO SET',
                                  style: TextStyle(
                                    color: isDragging
                                        ? arcColor
                                        : _DT.textSecondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    shadows: isDragging
                                        ? [
                                            Shadow(
                                              color: arcColor.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 6,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  const _ArcGaugePainter({required this.progress, this.isDragging = false});

  final double progress;
  final bool isDragging;

  static const _startAngle = math.pi * 0.75;
  static const _sweepFull = math.pi * 1.5;

  static final Map<String, TextPainter> _labelCache = {};

  static TextPainter _getLabel(String text) {
    return _labelCache.putIfAbsent(text, () {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepFull,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepFull * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 14 : 12
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepFull,
          colors: const [_DT.acCool, _DT.acWarm],
        ).createShader(rect),
    );

    final tipAngle = _startAngle + _sweepFull * progress;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    final tipColor = Color.lerp(_DT.acCool, _DT.acWarm, progress)!;

    canvas.drawCircle(
      tip,
      isDragging ? 16 : 10,
      Paint()
        ..color = tipColor.withValues(alpha: isDragging ? 0.50 : 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 14 : 9),
    );

    if (isDragging) {
      canvas.drawCircle(
        tip,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = tipColor.withValues(alpha: 0.7),
      );
    }

    canvas.drawCircle(tip, isDragging ? 6 : 5, Paint()..color = tipColor);

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.5;
    for (int i = 0; i <= 10; i++) {
      final a = _startAngle + (_sweepFull / 10) * i;
      final inner = center + Offset(math.cos(a), math.sin(a)) * (radius - 10);
      final outer = center + Offset(math.cos(a), math.sin(a)) * (radius + 2);
      canvas.drawLine(inner, outer, tickPaint);
    }

    _paintLabel(canvas, center, radius, _startAngle, '18');
    _paintLabel(canvas, center, radius, _startAngle + _sweepFull, '29');
  }

  void _paintLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String text,
  ) {
    final pos =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 18);
    final tp = _getLabel(text);
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.progress != progress || old.isDragging != isDragging;
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE PANEL (COOL / HEAT / DRY)
// ─────────────────────────────────────────────────────────────────────────────
class _ModePanel extends StatelessWidget {
  const _ModePanel({required this.state, required this.notifier});
  final MqttState state;
  final MqttNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ModeButton(
          label: 'COOL',
          icon: Icons.ac_unit,
          isActive: state.acMode == 'cool',
          color: _DT.acCool,
          onTap: () => notifier.sendAcCommand('AC_MODE_COOL'),
        ),
        _ModeButton(
          label: 'HEAT',
          icon: Icons.local_fire_department,
          isActive: state.acMode == 'heat',
          color: _DT.acWarm,
          onTap: () => notifier.sendAcCommand('AC_MODE_HEAT'),
        ),
        _ModeButton(
          label: 'DRY',
          icon: Icons.water_drop,
          isActive: state.acMode == 'dry',
          color: _DT.neonCyan,
          onTap: () => notifier.sendAcCommand('AC_MODE_DRY'),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isActive
                ? color.withValues(alpha: 0.8)
                : color.withValues(alpha: 0.2),
            width: isActive ? 2 : 1,
          ),
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? color : _DT.textSecondary,
              size: 20,
              shadows: isActive
                  ? [
                      Shadow(
                        color: color.withValues(alpha: 0.8),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : _DT.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAN & SWING PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _FanSwingPanel extends StatelessWidget {
  const _FanSwingPanel({required this.state, required this.notifier});
  final MqttState state;
  final MqttNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _FanButton(
          fan: state.acFan,
          onTap: () {
            final next = state.acFan >= 3 ? 1 : state.acFan + 1;
            notifier.sendAcCommand('AC_FAN_$next');
          },
        ),
        _SwingButton(
          isOn: state.acSwing,
          onTap: () => notifier.sendAcCommand(
            state.acSwing ? 'AC_SWING_OFF' : 'AC_SWING_ON',
          ),
        ),
      ],
    );
  }
}

class _FanButton extends StatelessWidget {
  const _FanButton({required this.fan, required this.onTap});
  final int fan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _DT.neonBlue.withValues(alpha: 0.4)),
          color: _DT.neonBlue.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.air, color: _DT.neonBlue, size: 18),
            const SizedBox(width: 8),
            Text(
              'FAN $fan',
              style: TextStyle(
                color: _DT.neonBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwingButton extends StatelessWidget {
  const _SwingButton({required this.isOn, required this.onTap});
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isOn ? _DT.neonGreen : _DT.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isOn
                ? _DT.neonGreen.withValues(alpha: 0.6)
                : _DT.textSecondary.withValues(alpha: 0.2),
          ),
          color: isOn
              ? _DT.neonGreen.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_alt, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              isOn ? 'SWING ON' : 'SWING OFF',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM PANEL (AUTO + SEASON)
// ─────────────────────────────────────────────────────────────────────────────
class _SystemPanel extends StatelessWidget {
  const _SystemPanel({required this.state, required this.notifier});
  final MqttState state;
  final MqttNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _AutoButton(
          isOn: state.acAutoMode,
          onTap: () => notifier.sendAutoMode(!state.acAutoMode),
        ),
        _SeasonButton(
          season: state.acSeason,
          onTap: () => notifier.sendSeason(
            state.acSeason == 'summer' ? 'winter' : 'summer',
          ),
        ),
      ],
    );
  }
}

class _AutoButton extends StatelessWidget {
  const _AutoButton({required this.isOn, required this.onTap});
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isOn ? _DT.neonPurple : _DT.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isOn
                ? _DT.neonPurple.withValues(alpha: 0.6)
                : _DT.textSecondary.withValues(alpha: 0.2),
          ),
          color: isOn
              ? _DT.neonPurple.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_mode, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              isOn ? 'AUTO ON' : 'AUTO OFF',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonButton extends StatelessWidget {
  const _SeasonButton({required this.season, required this.onTap});
  final String season;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSummer = season == 'summer';
    final color = isSummer ? _DT.neonOrange : _DT.acCool;
    final icon = isSummer ? Icons.wb_sunny : Icons.ac_unit;
    final label = isSummer ? 'SUMMER' : 'WINTER';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POWER BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.state, required this.notifier});
  final MqttState state;
  final MqttNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final isOn = state.acPower;
    final color = isOn ? _DT.neonRed : _DT.neonGreen;

    return Center(
      child: GestureDetector(
        onTap: () => notifier.sendAcCommand(isOn ? 'AC_OFF' : 'AC_ON'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.6), width: 3),
            color: color.withValues(alpha: 0.1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.power_settings_new,
                color: color,
                size: 40,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.8), blurRadius: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isOn ? 'OFF' : 'ON',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
