import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homesync/models/mqtt_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

part 'mqtt_provider.g.dart';

@riverpod
class MqttNotifier extends _$MqttNotifier {
  late MqttServerClient _client;
  bool _isConnecting = false;
  bool _firstConnection = true; // لتتبع أول اتصال

  @override
  MqttState build() {
    Future.delayed(const Duration(seconds: 1), () {
      _setupMqttAsync();
    });
    return const MqttState();
  }

  Future<void> _setupMqttAsync() async {
    if (_isConnecting || state.isConnected) return;
    _isConnecting = true;

    state = state.copyWith(isConnecting: true, error: null);

    const broker = 'ec718fd2e0b34835a04866dc30cbff70.s1.eu.hivemq.cloud';
    const port = 8883;
    const clientId = 'Flutter_Bashar_987';
    const username = 'mestoreus';
    const password = 'mesto1999@A';

    print('🔵 [MQTT] Starting connection to: $broker:$port');

    _client = MqttServerClient(broker, clientId)
      ..port = port
      ..secure = true
      ..keepAlivePeriod = 60
      ..autoReconnect = true
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected;

    final connMessage = MqttConnectMessage()
        .authenticateAs(username, password)
        .withClientIdentifier(clientId)
        .startClean()
        .keepAliveFor(60);
    _client.connectionMessage = connMessage;

    try {
      final status = await _client.connect();
      print('🟡 [MQTT] Connection status: ${status?.state}');

      if (status?.state == MqttConnectionState.connected) {
        print('🟢 [MQTT] Connected successfully!');
        state = state.copyWith(isConnected: true, isConnecting: false);
        _subscribe();
        _listenForMessages();

        // بعد أول اتصال، نطلب الحالة الحالية للبوابة
        if (_firstConnection) {
          _firstConnection = false;
          // نطلب حالة البوابة (اختياري)
          _requestGatewayStatus();
        }
      } else {
        print('🔴 [MQTT] Connection failed: ${status?.state}');
        state = state.copyWith(
          isConnecting: false,
          error: 'فشل الاتصال بالخادم',
        );
      }
    } catch (e) {
      print('🔴 [MQTT] ERROR: $e');
      state = state.copyWith(
        isConnecting: false,
        error: 'خطأ في الاتصال: ${e.toString().substring(0, 100)}',
      );
    } finally {
      _isConnecting = false;
    }
  }

  void _requestGatewayStatus() {
    // نطلب الحالة الحالية من البوابة
    const reqTopic = 'home/gateway/get';
    final builder = MqttClientPayloadBuilder();
    builder.addString('status');
    _client.publishMessage(reqTopic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [MQTT] Requested gateway status');
  }

  void _subscribe() {
    // المواضيع الصحيحة حسب كود ESP32
    const topics = [
      'home/lamp',
      'home/fan',
      'home/strip',
      'home/security',
      'home/sensors/temperature',
      'home/sensors/humidity',
      'home/sensors/gas',
      'home/sensors/gas/level',
      'home/sensors/motion',
      'home/gateway/status',
      'home/gateway/heartbeat',
      'home/ac/pair/ack', // للاقتران مع AC Node
      'home/gateway/error', // أخطاء البوابة
    ];

    for (var topic in topics) {
      _client.subscribe(topic, MqttQos.atLeastOnce);
      print('📡 [MQTT] Subscribed to: $topic');
    }
  }

  void _listenForMessages() {
    _client.updates?.listen((List<MqttReceivedMessage> messages) {
      for (var msg in messages) {
        final topic = msg.topic;
        final payload = MqttPublishPayload.bytesToStringAsString(
          (msg.payload as MqttPublishMessage).payload.message,
        );
        print('📩 [MQTT] Received: $topic = $payload');
        _handleIncoming(topic, payload);
      }
    });
  }

  void _handleIncoming(String topic, String payload) {
    switch (topic) {
      // الأجهزة
      case 'home/strip':
        state = state.copyWith(strip: payload == '1');
        break;
      case 'home/lamp':
        state = state.copyWith(lamp: payload == '1');
        break;
      case 'home/fan':
        state = state.copyWith(fan: payload == '1');
        break;
      case 'home/security':
        state = state.copyWith(security: payload.toUpperCase() == 'ON');
        break;

      // الحساسات
      case 'home/sensors/temperature':
        state = state.copyWith(temperature: double.tryParse(payload) ?? 0.0);
        break;
      case 'home/sensors/humidity':
        state = state.copyWith(humidity: double.tryParse(payload) ?? 0.0);
        break;
      case 'home/sensors/gas':
        state = state.copyWith(gas: int.tryParse(payload) ?? 0);
        break;
      case 'home/sensors/gas/level':
        print('📊 Gas level: $payload');
        // يمكن إضافة متغير gasLevel في MqttState إذا احتجت
        break;
      case 'home/sensors/motion':
        state = state.copyWith(motion: payload == '1');
        break;

      // حالة البوابة - تجاهل القيم القديمة
      case 'home/gateway/status':
        // إذا كانت القيمة offline والجهاز متصل، نتجاهلها (يمكن أن تكون قيمة قديمة)
        if (payload == 'offline' && state.isConnected && !_firstConnection) {
          print('🚪 Ignoring stale offline status');
          return;
        }
        print('🚪 Gateway status: $payload');
        // إذا كانت القيمة online، نحدث الحالة
        if (payload == 'online') {
          state = state.copyWith(gatewayOnline: true);
        } else if (payload == 'offline') {
          state = state.copyWith(gatewayOnline: false);
        }
        break;

      case 'home/gateway/heartbeat':
        print('💓 Gateway heartbeat: $payload');
        state = state.copyWith(lastHeartbeat: DateTime.now());
        break;

      case 'home/gateway/error':
        print('❌ Gateway error: $payload');
        break;

      case 'home/ac/pair/ack':
        print('🔐 Pairing ACK: $payload');
        if (payload == 'PAIR_OK') {
          state = state.copyWith(isPaired: true);
        } else if (payload == 'PAIR_RESET_OK') {
          state = state.copyWith(isPaired: false);
        }
        break;
    }
  }

  void sendCommand(String command) {
    if (!state.isConnected) {
      print('⚠️ [MQTT] Cannot send command: Not connected');
      return;
    }

    // تحديث الحالة محلياً
    switch (command) {
      case 'LAMP_ON':
        state = state.copyWith(lamp: true);
        break;
      case 'LAMP_OFF':
        state = state.copyWith(lamp: false);
        break;
      case 'STRIP_ON':
        state = state.copyWith(strip: true);
        break;
      case 'STRIP_OFF':
        state = state.copyWith(strip: false);
        break;
      case 'FAN_ON':
        state = state.copyWith(fan: true);
        break;
      case 'FAN_OFF':
        state = state.copyWith(fan: false);
        break;
      case 'SECURITY_ON':
        state = state.copyWith(security: true);
        break;
      case 'SECURITY_OFF':
        state = state.copyWith(security: false);
      case 'LED_ON':
        state = state.copyWith(led: true);
        break;
      case 'LED_OFF':
        state = state.copyWith(led: false);
        break;
    }

    // إرسال الأمر عبر MQTT
    const cmdTopic = 'home/commands';
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    _client.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [MQTT] Command sent: $command');
  }

  // دالة لإرسال أمر اقتران (Pairing)
  void sendPairingCommand() {
    if (!state.isConnected) {
      print('⚠️ [MQTT] Cannot send pairing command: Not connected');
      return;
    }
    sendCommand('PAIR_AC');
    print('🔐 [MQTT] Pairing command sent to AC Node');
  }

  void _onConnected() {
    state = state.copyWith(isConnected: true);
    print('🟢 [MQTT] Callback: Connected');
  }

  void _onDisconnected() {
    state = state.copyWith(isConnected: false);
    print('🔴 [MQTT] Callback: Disconnected');
  }
}
