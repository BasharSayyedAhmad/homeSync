import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homesync/features/head_pose/head_pose_screen.dart';
import 'package:homesync/features/providers/mqtt_provider.dart';
import 'package:homesync/features/providers/voice_provider.dart';
import 'package:homesync/models/mqtt_state.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mqttState = ref.watch(mqttNotifierProvider);
    final voiceState = ref.watch(voiceNotifierProvider);
    final voiceNotifier = ref.read(voiceNotifierProvider.notifier);
    final mqttNotifier = ref.read(mqttNotifierProvider.notifier);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: voiceState.isListening
            ? voiceNotifier.stopListening
            : () => voiceNotifier.startListening(),
        icon: Icon(voiceState.isListening ? Icons.mic_off : Icons.mic),
        label: Text(voiceState.isListening ? "جاري الاستماع..." : "أمر صوتي"),
        backgroundColor: voiceState.isListening ? Colors.red : Colors.green,
      ),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HeadPoseScreen()),
            );
          },
          icon: Icon(Icons.remove_red_eye),
        ),
        // title: const Text('KNX Smart Home'),
        backgroundColor: Colors.blueGrey[800],
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.wifi,
                  color: mqttState.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  mqttState.isConnected ? 'MQTT ON' : 'MQTT OFF',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // لوحة الحساسات
            _buildSensorPanel(mqttState),
            const SizedBox(height: 20),

            // لوحة التحكم
            _buildControlPanel(mqttState, mqttNotifier),
            const SizedBox(height: 20),

            // لوحة الأمان
            _buildSecurityPanel(mqttState.security),

            // Voice Feedback
            if (voiceState.feedback.isNotEmpty)
              _buildVoiceFeedback(voiceState.feedback, voiceNotifier),

            // النص المتعرف عليه
            if (voiceState.recognizedText.isNotEmpty)
              _buildRecognizedText(voiceState.recognizedText),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorPanel(MqttState state) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 قراءات الحساسات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _sensorChip(
                    Icons.thermostat,
                    '🌡️ ${state.temperature.toStringAsFixed(1)}°C',
                    Colors.red,
                  ),
                  _sensorChip(
                    Icons.water_drop,
                    '💧 ${state.humidity.toStringAsFixed(1)}%',
                    Colors.blue,
                  ),
                  _sensorChip(Icons.air, '💨 غاز: ${state.gas}', Colors.brown),
                  _sensorChip(
                    Icons.directions_walk,
                    state.motion ? '🚶 حركة' : '🛑 ساكن',
                    state.motion ? Colors.orange : Colors.grey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
      backgroundColor: Colors.grey[200],
    );
  }

  Widget _buildControlPanel(MqttState state, MqttNotifier notifier) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎛️ التحكم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _controlButton(
                  '💡 lamp',
                  state.lamp,
                  () =>
                      notifier.sendCommand(state.lamp ? 'LAMP_OFF' : 'LAMP_ON'),
                ),
                _controlButton(
                  'led',
                  state.led,
                  () => notifier.sendCommand(state.led ? 'LED_OFF' : 'LED_ON'),
                ),
                _controlButton(
                  '🌀 fan',
                  state.fan,
                  () => notifier.sendCommand(state.fan ? 'FAN_OFF' : 'FAN_ON'),
                ),
                _controlButton(
                  '✨ Strip',
                  state.strip,
                  () => notifier.sendCommand(
                    state.strip ? 'STRIP_OFF' : 'STRIP_ON',
                  ),
                ),
                _controlButton(
                  '🔐 security',
                  state.security,
                  () => notifier.sendCommand(
                    state.security ? 'SECURITY_OFF' : 'SECURITY_ON',
                  ),
                ),
                _controlButton(
                  '🚪 door',
                  false,
                  () => notifier.sendCommand('DOOR_POS:90'),
                ),
                _controlButton(
                  '🛞 garage',
                  false,
                  () => notifier.sendCommand('GARAGE_POS:45'),
                ),
                _controlButton(
                  '🌙 Night mode',
                  false,
                  () => notifier.sendCommand('SCENE_NIGHT'),
                ),
                _controlButton(
                  '🏠 وضع المنزل',
                  false,
                  () => notifier.sendCommand('SCENE_HOME'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton(String label, bool isOn, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(isOn ? Icons.power_settings_new : Icons.power_off, size: 18),
      label: Text('$label ${isOn ? 'ON' : 'OFF'}'),
      style: ElevatedButton.styleFrom(
        backgroundColor: isOn ? Colors.green.shade50 : Colors.grey.shade200,
        foregroundColor: isOn ? Colors.green.shade800 : Colors.grey.shade800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSecurityPanel(bool isSecurityOn) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🚨 حالة الأمن',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.security,
                  color: isSecurityOn ? Colors.red : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  isSecurityOn ? 'نظام الحماية مفعل' : 'نظام الحماية معطل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isSecurityOn ? Colors.red : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceFeedback(String feedback, VoiceNotifier notifier) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: feedback.contains('✅')
            ? Colors.green.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: feedback.contains('✅') ? Colors.green : Colors.red,
        ),
      ),
      child: Row(
        children: [
          Icon(
            feedback.contains('✅') ? Icons.check_circle : Icons.error,
            color: feedback.contains('✅') ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(feedback)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => notifier.clearFeedback(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognizedText(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text('🎙️: "$text"', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
