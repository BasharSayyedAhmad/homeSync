import 'dart:async';
import 'package:flutter/material.dart';
import 'package:homesync/core/constant/voice_command.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class TestKnx extends StatefulWidget {
  const TestKnx({super.key});

  @override
  State<TestKnx> createState() => _TestKnxState();
}

class _TestKnxState extends State<TestKnx> {
  late MqttServerClient client;
  bool mqttConnected = false;
  bool _connecting = false;

  // 🔐 بيانات الاتصال بـ HiveMQ Cloud (تأكد من صحتها)
  final String broker = 'ec718fd2e0b34835a04866dc30cbff70.s1.eu.hivemq.cloud';
  final int port = 8883;
  final String clientId = 'Flutter_Bashar_987';
  final String username = 'mestoreus';
  final String password = 'mesto1999@A';

  // 📡 مواضيع MQTT (متطابقة مع الـ ESP32)
  final String cmdTopic = 'home/commands'; // إرسال الأوامر
  final String stripTopic = 'home/strip';
  final String lampTopic = 'home/lamp'; // استقبال حالة اللمبة
  final String fanTopic = 'home/fan'; // استقبال حالة المروحة
  final String tempTopic = 'home/temp'; // استقبال الحرارة
  final String humTopic = 'home/hum'; // استقبال الرطوبة
  final String gasTopic = 'home/gas'; // استقبال الغاز
  final String motionTopic = 'home/motion'; // استقبال الحركة
  final String securityTopic = 'home/security'; // استقبال حالة الأمان

  // 🧠 متغيرات الحالة
  bool lamp = false;
  bool strip = false;
  bool fan = false;
  bool security = false;
  bool motion = false;
  double temperature = 0.0;
  double humidity = 0.0;
  int gas = 0;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _voiceText = "";

  @override
  void initState() {
    super.initState();
    setupMqtt();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    if (mqttConnected) {
      client.disconnect();
    }
    super.dispose();
  }

  Future<void> setupMqtt() async {
    if (_connecting) return;
    _connecting = true;

    print("🟡 Connecting to MQTT broker...");

    client = MqttServerClient(broker, clientId)
      ..port = port
      ..secure =
          true // TLS/SSL
      ..keepAlivePeriod = 60
      ..autoReconnect = true
      ..logging(on: true) // لمتابعة الأخطاء في الـ console
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected;

    // 🔑 استخدام WebSockets إذا كان المنفذ 8883 محظوراً (اختياري)
    // client.useWebSocket = true;
    // client.port = 443;
    // 🔐 إعدادات المصادقة
    final connMessage = MqttConnectMessage()
        .authenticateAs(username, password)
        .withClientIdentifier(clientId)
        .startClean()
        .keepAliveFor(60);
    client.connectionMessage = connMessage;

    try {
      final status = await client.connect();
      print("🟡 MQTT connection status: $status");

      if (status?.state == MqttConnectionState.connected) {
        setState(() => mqttConnected = true);
        print("🟢 MQTT Connected successfully!");

        // الاشتراك في المواضيع (Topics)
        _subscribe();

        // بدء الاستماع للرسائل
        _listenForMessages();
      } else {
        print("🔴 MQTT connection failed: ${status?.state}");
        _showError("فشل الاتصال بالخادم");
      }
    } catch (e) {
      print("🔴 MQTT ERROR: $e");
      _showError("خطأ في الاتصال: $e");
    } finally {
      _connecting = false;
    }
  }

  void _subscribe() {
    client.subscribe(lampTopic, MqttQos.atLeastOnce);
    client.subscribe(fanTopic, MqttQos.atLeastOnce);
    client.subscribe(tempTopic, MqttQos.atLeastOnce);
    client.subscribe(humTopic, MqttQos.atLeastOnce);
    client.subscribe(gasTopic, MqttQos.atLeastOnce);
    client.subscribe(motionTopic, MqttQos.atLeastOnce);
    client.subscribe(securityTopic, MqttQos.atLeastOnce);
    print("✅ Subscribed to all topics");
  }

  void _listenForMessages() {
    client.updates?.listen((List<MqttReceivedMessage> messages) {
      for (var msg in messages) {
        final topic = msg.topic;
        final payload = MqttPublishPayload.bytesToStringAsString(
          (msg.payload as MqttPublishMessage).payload.message,
        );
        _handleIncoming(topic, payload);
      }
    });
  }

  void _handleIncoming(String topic, String payload) {
    print("📩 Received: $topic = $payload");
    setState(() {
      switch (topic) {
        case 'home/strip':
          strip = payload == '1';
          break;
        case 'home/lamp':
          lamp = payload == '1';
          break;
        case 'home/fan':
          fan = payload == '1';
          break;
        case 'home/security':
          security = payload.toUpperCase() == 'ON';
          break;
        case 'home/motion':
          motion = payload == '1';
          break;
        case 'home/temp':
          temperature = double.tryParse(payload) ?? 0.0;
          break;
        case 'home/hum':
          humidity = double.tryParse(payload) ?? 0.0;
          break;
        case 'home/gas':
          gas = int.tryParse(payload) ?? 0;
          break;
      }
    });
  }

  // void sendCommand(String command) {
  //   if (!mqttConnected) {
  //     _showError("الجهاز غير متصل بشبكة MQTT");
  //     return;
  //   }

  //   final builder = MqttClientPayloadBuilder();
  //   builder.addString(command);
  //   client.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
  //   print("📤 Command sent: $command");
  // }
  void sendCommand(String command) {
    if (!mqttConnected) {
      _showError("الجهاز غير متصل بشبكة MQTT");
      return;
    }

    // 🔥 تحديث الحالة مباشرة (Toggle)
    setState(() {
      if (command == 'LAMP_ON') lamp = true;
      if (command == 'LAMP_OFF') lamp = false;
      if (command == "STRIP_ON") strip = true;
      if (command == "STRIP_OFF") strip = false;
      if (command == 'FAN_ON') fan = true;
      if (command == 'FAN_OFF') fan = false;
      if (command == 'SECURITY_ON') security = true;
      if (command == 'SECURITY_OFF') security = false;
    });

    // إرسال الأمر عبر MQTT
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    client.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);

    print("📤 Command sent: $command");
  }

  void _onConnected() {
    setState(() => mqttConnected = true);
    print("🟢 MQTT Callback: Connected");
  }

  void _onDisconnected() {
    setState(() => mqttConnected = false);
    print("🔴 MQTT Callback: Disconnected");
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void handleVoiceCommand(String text) {
    text = text.trim();

    // لمبة
    if (lightOnCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("LAMP_ON");
    } else if (lightOffCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("LAMP_OFF");
    }
    // مروحة
    else if (fanOnCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("FAN_ON");
    } else if (fanOffCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("FAN_OFF");
    } else if (stripOnCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("STRIP_ON");
    } else if (stripOffCommands.any((cmd) => text.contains(cmd))) {
      sendCommand("STRIP_OFF");
    }
    // أمان
    else if (text.contains("شغل الأمان") || text.contains("فعل الأمان")) {
      sendCommand("SECURITY_ON");
    } else if (text.contains("طفي الأمان") || text.contains("وقف الأمان")) {
      sendCommand("SECURITY_OFF");
    }

    print("🎤 Voice Command Detected: $text");
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == "done") {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        print("Speech ERROR: $error");
      },
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ar-SY",
        onResult: (result) {
          setState(() {
            _voiceText = result.recognizedWords;
          });

          // 🔥 تحليل الصوت وإرسال الأمر
          handleVoiceCommand(result.recognizedWords);
        },
      );
    }
  }

  void stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _isListening ? stopListening : startListening,
        child: Icon(Icons.mic),
      ),
      appBar: AppBar(
        title: const Text('KNX Smart Home'),
        backgroundColor: Colors.blueGrey[800],
        actions: [_buildConnectionStatus()],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            _buildSensorPanel(),
            const SizedBox(height: 20),
            _buildControlPanel(),
            const SizedBox(height: 20),
            _buildSecurityPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Icon(Icons.wifi, color: mqttConnected ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          Text(
            mqttConnected ? 'MQTT ON' : 'MQTT OFF',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorPanel() {
    return Card(
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
                    '🌡️ ${temperature.toStringAsFixed(1)}°C',
                    Colors.red,
                  ),
                  _sensorChip(
                    Icons.water_drop,
                    '💧 ${humidity.toStringAsFixed(1)}%',
                    Colors.blue,
                  ),
                  _sensorChip(Icons.air, '💨 غاز: $gas', Colors.brown),
                  _sensorChip(
                    Icons.directions_walk,
                    motion ? '🚶 حركة' : '🛑 ساكن',
                    motion ? Colors.orange : Colors.grey,
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

  Widget _buildControlPanel() {
    return Card(
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
                  '💡 لمبة',
                  lamp ? 'إطفاء' : 'تشغيل',
                  () => sendCommand(lamp ? 'LAMP_OFF' : 'LAMP_ON'),
                ),
                _controlButton(
                  '🌀 مروحة',
                  fan ? 'إطفاء' : 'تشغيل',
                  () => sendCommand(fan ? 'FAN_OFF' : 'FAN_ON'),
                ),
                _controlButton(
                  '🔐 أمان',
                  security ? 'إيقاف' : 'تفعيل',
                  () => sendCommand(security ? 'SECURITY_OFF' : 'SECURITY_ON'),
                ),
                _controlButton(
                  '🚪 باب',
                  'فتح 90%',
                  () => sendCommand('DOOR_POS:90'),
                ),
                _controlButton(
                  "Strip",
                  strip ? 'إطفاء' : 'تشغيل',
                  () => sendCommand(strip ? 'STRIP_OFF' : 'STRIP_ON'),
                ),
                _controlButton(
                  '🛞 كراج',
                  'غلق 45%',
                  () => sendCommand('GARAGE_POS:45'),
                ),
                _controlButton(
                  '🌙 وضع الليل',
                  'تشغيل',
                  () => sendCommand('SCENE_NIGHT'),
                ),
                _controlButton(
                  '🏠 وضع المنزل',
                  'تشغيل',
                  () => sendCommand('SCENE_HOME'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton(String label, String action, VoidCallback onPressed) {
    return ElevatedButton(onPressed: onPressed, child: Text('$label: $action'));
  }

  Widget _buildSecurityPanel() {
    return Card(
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
                  color: security ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(security ? 'نظام الحماية مفعل' : 'نظام الحماية معطل'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
