import 'package:homesync/models/mqtt_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../core/services/secure_storage_service.dart';
import '../../core/services/hive_service.dart';

part 'mqtt_provider.g.dart';

@riverpod
class MqttNotifier extends _$MqttNotifier {
  late MqttServerClient _client;
  bool _isConnecting = false;
  bool _firstConnection = true;
  bool _isInitialized = false;

  // ✅ إضافة متغير لتتبع حالة تحميل البيانات
  bool _credentialsLoaded = false;

  String? _broker;
  String? _username;
  String? _password;
  String? _clientId;

  @override
  MqttState build() {
    if (!_isInitialized) {
      _isInitialized = true;
      Future.microtask(() => _loadAndSetupMqtt());
    }
    return const MqttState();
  }

  Future<void> _loadAndSetupMqtt() async {
    if (_isConnecting || state.isConnected) {
      print('⚠️ [MQTT] Already connecting or connected, skipping...');
      return;
    }

    print('🔐 [MQTT] Loading credentials from secure storage...');
    final creds = await SecureStorageService.getMQTTcredentials();
    _broker = creds['broker'];
    _username = creds['username'];
    _password = creds['password'];
    _clientId = creds['clientId'];

    // ✅ علامة أن البيانات تحملت
    _credentialsLoaded = true;

    print(
      '🔐 [MQTT] Credentials loaded - Broker: $_broker, Username: $_username',
    );

    if (_broker == null || _broker!.isEmpty) {
      print('⚠️ [MQTT] No credentials found. Please login first.');
      state = state.copyWith(
        isConnected: false,
        error: 'الرجاء تسجيل الدخول أولاً',
        needsLogin: true,
      );
      return;
    }

    await _setupMqttAsync();
  }

  Future<void> _setupMqttAsync() async {
    // ✅ انتظر حتى تتحمل البيانات (بحد أقصى 5 ثواني)
    int waitCount = 0;
    while (!_credentialsLoaded && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (!_credentialsLoaded) {
      print('❌ [MQTT] Timeout waiting for credentials');
      state = state.copyWith(needsLogin: true, isConnecting: false);
      return;
    }

    // ✅ الآن تأكد من البيانات بعد الانتظار
    if (_broker == null || _broker!.isEmpty) {
      print('❌ [MQTT] Broker is null or empty');
      state = state.copyWith(needsLogin: true, isConnecting: false);
      return;
    }

    if (_username == null || _username!.isEmpty) {
      print('❌ [MQTT] Username is null or empty');
      state = state.copyWith(needsLogin: true, isConnecting: false);
      return;
    }

    if (_password == null || _password!.isEmpty) {
      print('❌ [MQTT] Password is null or empty');
      state = state.copyWith(needsLogin: true, isConnecting: false);
      return;
    }

    if (_isConnecting || state.isConnected) return;

    _isConnecting = true;
    state = state.copyWith(isConnecting: true, error: null, needsLogin: false);

    print('🔵 [MQTT] Starting connection to: $_broker');

    _client = MqttServerClient(_broker!, _clientId ?? 'Flutter_Client')
      ..port = 8883
      ..secure = true
      ..keepAlivePeriod = 60
      ..autoReconnect = true
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected;

    final connMessage = MqttConnectMessage()
        .authenticateAs(_username!, _password!)
        .withClientIdentifier(_clientId ?? 'Flutter_Client')
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

        if (_firstConnection) {
          _firstConnection = false;
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

  Future<bool> loginWithCredentials({
    required String broker,
    required String username,
    required String password,
    String? clientId,
  }) async {
    await SecureStorageService.saveMQTTcredentials(
      broker: broker,
      username: username,
      password: password,
      clientId: clientId ?? 'Flutter_${DateTime.now().millisecondsSinceEpoch}',
    );

    _broker = broker;
    _username = username;
    _password = password;
    _clientId = clientId;
    _credentialsLoaded = true; // ✅ علامة أن البيانات تحملت

    await _setupMqttAsync();

    if (state.isConnected) {
      final session = UserSession(
        username: username,
        isLoggedIn: true,
        loginTime: DateTime.now(),
        sessionExpiry: DateTime.now().add(const Duration(days: 30)),
      );
      await HiveService.saveSession(session);
      return true;
    }

    return false;
  }

  Future<void> logout() async {
    if (_client.connectionStatus?.state == MqttConnectionState.connected) {
      _client.disconnect();
    }

    await SecureStorageService.clearMQTTcredentials();
    await HiveService.clearSession();

    state = const MqttState().copyWith(needsLogin: true);
    _broker = null;
    _username = null;
    _password = null;
    _clientId = null;
    _isConnecting = false;
    _firstConnection = true;
    _isInitialized = false;
    _credentialsLoaded = false; // ✅ إعادة تعيين

    print('🔴 [MQTT] Logged out and credentials cleared');
  }

  void _requestGatewayStatus() {
    const reqTopic = 'home/gateway/get';
    final builder = MqttClientPayloadBuilder();
    builder.addString('status');
    _client.publishMessage(reqTopic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [MQTT] Requested gateway status');
  }

  void _subscribe() {
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
      'home/ac/pair/ack',
      'home/gateway/error',
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
        break;
      case 'home/sensors/motion':
        state = state.copyWith(motion: payload == '1');
        break;
      case 'home/gateway/status':
        if (payload == 'offline' && state.isConnected && !_firstConnection) {
          print('🚪 Ignoring stale offline status');
          return;
        }
        print('🚪 Gateway status: $payload');
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
        break;
      case 'LED_ON':
        state = state.copyWith(led: true);
        break;
      case 'LED_OFF':
        state = state.copyWith(led: false);
        break;
    }

    const cmdTopic = 'home/commands';
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    _client.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [MQTT] Command sent: $command');
  }

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
