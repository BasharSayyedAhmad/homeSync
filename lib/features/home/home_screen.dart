// features/home/home_screen.dart
//
// Futuristic Cyber-Command Dashboard — KNX Smart Home
// Dark Glassmorphism · Neon Glows · Ambient Responsive Effects
//
// Architecture rules obeyed:
//  • HomeScreen extends ConsumerWidget — Riverpod-only business state
//  • No setState in HomeScreen; sub-widgets use ValueNotifier for local UI state
//  • ref.watch() for state, ref.read().notifier for actions
//
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homesync/core/services/gas_notification_service.dart';
import 'package:homesync/features/ac/ac_remote_screen.dart';
import 'package:homesync/features/services/eye_tracking/widgets/iris_gaze_button.dart';
import 'package:homesync/features/services/head_pose/head_pose_screen.dart';
import 'package:homesync/features/providers/mqtt_provider.dart';
import 'package:homesync/features/providers/voice_provider.dart';
import 'package:homesync/models/mqtt_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
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
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mqttState = ref.watch(mqttNotifierProvider);
    final voiceState = ref.watch(voiceNotifierProvider);
    final voiceNotifier = ref.read(voiceNotifierProvider.notifier);
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
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(label: 'SENSOR MATRIX'),
                  const SizedBox(height: 8),
                  _SensorPanel(state: mqttState),
                  const SizedBox(height: 20),

                  _SectionLabel(label: 'COMMAND MATRIX'),
                  const SizedBox(height: 8),
                  _ControlMatrix(state: mqttState, notifier: mqttNotifier),
                  const SizedBox(height: 20),
                  IrisGazeButton(
                    onGazeChanged: (gaze) {
                      print('اتجاه العين: $gaze');
                      // ← هنا ربطه بأوامرك
                    },
                  ),
                ],
              ),
            ),

            if (voiceState.isListening)
              _VoiceListeningOverlay(onStop: voiceNotifier.stopListening),

            if (voiceState.feedback.isNotEmpty)
              _VoiceToast(
                feedback: voiceState.feedback,
                onDismiss: voiceNotifier.clearFeedback,
              ),

            if (voiceState.recognizedText.isNotEmpty)
              _RecognizedTextToast(text: voiceState.recognizedText),
          ],
        ),
      ),
      floatingActionButton: _VoiceFab(
        isListening: voiceState.isListening,
        onPressed: voiceState.isListening
            ? voiceNotifier.stopListening
            : () => voiceNotifier.startListening(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMBIENT TRANSPARENT APP BAR (with GAS Alert)
// ─────────────────────────────────────────────────────────────────────────────
class _CyberAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CyberAppBar({required this.isConnected, required this.gasLevel});
  final bool isConnected;
  final String gasLevel;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: _HudIconButton(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => HeadPoseScreen()),
        ),
      ),
      title: const Text(
        'KNX COMMAND',
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
// GAS ALERT BUTTON (AppBar)
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
// GLASSMORPHIC CARD BASE
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
// PULSING NEON DOT
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
// HUD ICON BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _HudIconButton extends StatefulWidget {
  const _HudIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HudIconButton> createState() => _HudIconButtonState();
}

class _HudIconButtonState extends State<_HudIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _ctrl.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(36, 36),
                  painter: _HaloPainter(),
                ),
              ),
              Icon(
                Icons.radar,
                color: _DT.neonBlue,
                size: 22,
                shadows: [
                  Shadow(
                    color: _DT.neonBlue.withValues(alpha: 0.8),
                    blurRadius: 12,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      0,
      math.pi * 1.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = SweepGradient(
          colors: [Colors.transparent, _DT.neonBlue.withValues(alpha: 0.9)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _SensorPanel extends StatelessWidget {
  const _SensorPanel({required this.state});
  final MqttState state;

  bool get _isCritical => state.motion || state.gas > 400;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      isAlert: _isCritical,
      glowColor: _DT.neonBlue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileW = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: tileW,
                child: _SensorTile(
                  icon: Icons.thermostat,
                  label: 'TEMP',
                  value: '${state.temperature.toStringAsFixed(1)}°C',
                  color: state.temperature > 30
                      ? _DT.neonOrange
                      : _DT.neonGreen,
                ),
              ),
              SizedBox(
                width: tileW,
                child: _SensorTile(
                  icon: Icons.water_drop,
                  label: 'HUMIDITY',
                  value: '${state.humidity.toStringAsFixed(1)}%',
                  color: _DT.neonBlue,
                ),
              ),
              SizedBox(
                width: tileW,
                child: _SensorTile(
                  icon: Icons.air,
                  label: 'GAS',
                  value: '${state.gas} ppm',
                  color: state.gas > 400 ? _DT.neonRed : _DT.neonOrange,
                  isAlert: state.gas > 400,
                ),
              ),
              SizedBox(
                width: tileW,
                child: _SensorTile(
                  icon: state.motion
                      ? Icons.directions_walk
                      : Icons.accessibility_new,
                  label: 'MOTION',
                  value: state.motion ? 'DETECTED' : 'CLEAR',
                  color: state.motion ? _DT.neonOrange : _DT.textSecondary,
                  isAlert: state.motion,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SensorTile extends StatefulWidget {
  const _SensorTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isAlert = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isAlert;

  @override
  State<_SensorTile> createState() => _SensorTileState();
}

class _SensorTileState extends State<_SensorTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _glow = Tween(
      begin: 0.25,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (widget.isAlert) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_SensorTile old) {
    super.didUpdateWidget(old);
    if (widget.isAlert && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isAlert && _ctrl.isAnimating) {
      _ctrl
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.color.withValues(
              alpha: widget.isAlert ? _glow.value : 0.2,
            ),
          ),
          boxShadow: widget.isAlert
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: _glow.value * 0.3),
                    blurRadius: 18,
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: widget.color, size: 18),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: _DT.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.value,
              style: TextStyle(
                color: widget.color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    color: widget.color.withValues(alpha: 0.55),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND MATRIX (10 tiles: 3×3 + 1 row)
// ─────────────────────────────────────────────────────────────────────────────
class _ControlMatrix extends StatelessWidget {
  const _ControlMatrix({required this.state, required this.notifier});
  final MqttState state;
  final MqttNotifier notifier;

  List<_TileData> _buildTiles(BuildContext context) => [
    _TileData(
      icon: Icons.lightbulb_outline,
      label: 'LAMP',
      isOn: state.lamp,
      color: _DT.neonYellow,
      onTap: () => notifier.sendCommand(state.lamp ? 'LAMP_OFF' : 'LAMP_ON'),
    ),
    _TileData(
      icon: Icons.linear_scale,
      label: 'LED',
      isOn: state.led,
      color: _DT.neonPurple,
      onTap: () => notifier.sendCommand(state.led ? 'LED_OFF' : 'LED_ON'),
    ),
    _TileData(
      icon: Icons.air,
      label: 'FAN',
      isOn: state.fan,
      color: _DT.neonBlue,
      onTap: () => notifier.sendCommand(state.fan ? 'FAN_OFF' : 'FAN_ON'),
    ),
    _TileData(
      icon: Icons.wb_sunny_outlined,
      label: 'WHITE',
      isOn: false,
      color: Colors.white,
      onTap: () => notifier.sendCommand('LED_WHITE'),
    ),
    _TileData(
      icon: Icons.circle,
      label: 'RED',
      isOn: false,
      color: _DT.neonRed,
      onTap: () => notifier.sendCommand('LED_RED'),
    ),
    _TileData(
      icon: Icons.add,
      label: 'DIM+',
      isOn: false,
      color: _DT.neonGreen,
      onTap: () => notifier.sendCommand('LED_DIM_UP'),
    ),
    _TileData(
      icon: Icons.remove,
      label: 'DIM-',
      isOn: false,
      color: _DT.neonGreen,
      onTap: () => notifier.sendCommand('LED_DIM_DOWN'),
    ),
    _TileData(
      icon: Icons.meeting_room,
      label: 'DOOR',
      isOn: state.doorOpen,
      color: _DT.neonOrange,
      onTap: () =>
          notifier.sendCommand(state.doorOpen ? 'DOOR_CLOSE' : 'DOOR_OPEN'),
    ),
    _TileData(
      icon: Icons.garage,
      label: 'GARAGE',
      isOn: state.garageOpen,
      color: _DT.neonGreen,
      onTap: () => notifier.sendCommand(
        state.garageOpen ? 'GARAGE_CLOSE' : 'GARAGE_OPEN',
      ),
    ),
    _TileData(
      icon: Icons.ac_unit,
      label: 'AC',
      isOn: state.acPower,
      color: _DT.acCool,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AcRemoteScreen()),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = _buildTiles(context);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const crossCount = 3;
        const spacing = 12.0;
        final tileSize =
            (constraints.maxWidth - spacing * (crossCount - 1)) / crossCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles
              .map(
                (t) => SizedBox(
                  width: tileSize,
                  height: tileSize,
                  child: _ControlTile(
                    icon: t.icon,
                    label: t.label,
                    isOn: t.isOn,
                    neonColor: t.color,
                    onTap: t.onTap,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _TileData {
  const _TileData({
    required this.icon,
    required this.label,
    required this.isOn,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isOn;
  final Color color;
  final VoidCallback onTap;
}

class _ControlTile extends StatefulWidget {
  const _ControlTile({
    required this.icon,
    required this.label,
    required this.isOn,
    required this.neonColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isOn;
  final Color neonColor;
  final VoidCallback onTap;

  @override
  State<_ControlTile> createState() => _ControlTileState();
}

class _ControlTileState extends State<_ControlTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(_) => _press.reverse();
  void _up(_) {
    _press.forward();
    widget.onTap();
  }

  void _cancel() => _press.forward();

  @override
  Widget build(BuildContext context) {
    const offIcon = Color(0xFF484F58);
    const offBg = Color(0xFF161B22);
    const offBorder = Color(0x0FFFFFFF);

    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, __) => Transform.scale(
          scale: _press.value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: widget.isOn
                  ? widget.neonColor.withValues(alpha: 0.12)
                  : offBg,
              border: Border.all(
                color: widget.isOn
                    ? widget.neonColor.withValues(alpha: 0.45)
                    : offBorder,
              ),
              boxShadow: widget.isOn
                  ? [
                      BoxShadow(
                        color: widget.neonColor.withValues(alpha: 0.35),
                        blurRadius: 22,
                      ),
                      BoxShadow(
                        color: widget.neonColor.withValues(alpha: 0.15),
                        blurRadius: 44,
                        spreadRadius: 4,
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 26,
                  color: widget.isOn ? widget.neonColor : offIcon,
                  shadows: widget.isOn
                      ? [
                          Shadow(
                            color: widget.neonColor.withValues(alpha: 0.9),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isOn ? widget.neonColor : offIcon,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: widget.isOn
                        ? widget.neonColor.withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.07),
                    boxShadow: widget.isOn
                        ? [
                            BoxShadow(
                              color: widget.neonColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
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
// VOICE FAB
// ─────────────────────────────────────────────────────────────────────────────
class _VoiceFab extends StatefulWidget {
  const _VoiceFab({required this.isListening, required this.onPressed});
  final bool isListening;
  final VoidCallback onPressed;

  @override
  State<_VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<_VoiceFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ringScale = Tween(
      begin: 1.0,
      end: 1.6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ringOpacity = Tween(
      begin: 0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_VoiceFab old) {
    super.didUpdateWidget(old);
    if (widget.isListening) {
      _ctrl.repeat();
    } else {
      _ctrl
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isListening ? _DT.neonRed : _DT.neonGreen;
    final fab = FloatingActionButton(
      onPressed: widget.onPressed,
      backgroundColor: color.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      elevation: 0,
      child: Icon(
        widget.isListening ? Icons.mic_off : Icons.mic,
        color: color,
        shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 12)],
      ),
    );

    if (!widget.isListening) return fab;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Opacity(
            opacity: _ringOpacity.value,
            child: Transform.scale(
              scale: _ringScale.value,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
            ),
          ),
        ),
        fab,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOICE LISTENING OVERLAY
// ─────────────────────────────────────────────────────────────────────────────
class _VoiceListeningOverlay extends StatefulWidget {
  const _VoiceListeningOverlay({required this.onStop});
  final VoidCallback onStop;

  @override
  State<_VoiceListeningOverlay> createState() => _VoiceListeningOverlayState();
}

class _VoiceListeningOverlayState extends State<_VoiceListeningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _DT.neonGreen.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.82),
                ],
              ),
              border: Border(
                top: BorderSide(color: _DT.neonGreen.withValues(alpha: 0.18)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => SizedBox(
                    height: 60,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _WavePainter(phase: _ctrl.value * 2 * math.pi),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'LISTENING...',
                  style: TextStyle(
                    color: _DT.neonGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    shadows: [
                      Shadow(
                        color: _DT.neonGreen.withValues(alpha: 0.6),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.phase});
  final double phase;

  static const _waves = [
    (amplitude: 14.0, frequency: 1.5, color: _DT.neonGreen, opacity: 0.90),
    (amplitude: 10.0, frequency: 2.2, color: _DT.neonBlue, opacity: 0.55),
    (amplitude: 7.0, frequency: 3.0, color: _DT.neonCyan, opacity: 0.30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    const step = 2.0;
    for (final w in _waves) {
      final path = Path()..moveTo(0, midY);
      for (double x = step; x <= size.width; x += step) {
        path.lineTo(
          x,
          midY +
              w.amplitude *
                  math.sin(
                    (x / size.width) * w.frequency * 2 * math.pi + phase,
                  ),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = w.color.withValues(alpha: w.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.phase != phase;
}

// ─────────────────────────────────────────────────────────────────────────────
// VOICE TOAST
// ─────────────────────────────────────────────────────────────────────────────
class _VoiceToast extends StatefulWidget {
  const _VoiceToast({required this.feedback, required this.onDismiss});
  final String feedback;
  final VoidCallback onDismiss;

  @override
  State<_VoiceToast> createState() => _VoiceToastState();
}

class _VoiceToastState extends State<_VoiceToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOk = widget.feedback.contains('✅');
    final color = isOk ? _DT.neonGreen : _DT.neonRed;
    return Positioned(
      top: 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOk ? Icons.check_circle_outline : Icons.error_outline,
                      color: color,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.feedback,
                        style: const TextStyle(
                          color: _DT.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: _DT.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECOGNIZED TEXT TOAST
// ─────────────────────────────────────────────────────────────────────────────
class _RecognizedTextToast extends StatefulWidget {
  const _RecognizedTextToast({required this.text});
  final String text;

  @override
  State<_RecognizedTextToast> createState() => _RecognizedTextToastState();
}

class _RecognizedTextToastState extends State<_RecognizedTextToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) {
            setState(() {
              _visible = false;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Positioned(
      top: 68,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.record_voice_over,
                    size: 13,
                    color: _DT.neonBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"${widget.text}"',
                      style: const TextStyle(
                        color: _DT.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
