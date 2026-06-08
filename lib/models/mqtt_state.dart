class MqttState {
  final bool isConnected;
  final bool isConnecting;
  final bool needsLogin;
  final String? error;
  final bool lamp;
  final bool strip;
  final bool fan;
  final bool security;
  final bool led;
  final double temperature;
  final double humidity;
  final int gas;
  final bool motion;
  final bool gatewayOnline;
  final bool isPaired;
  final DateTime? lastHeartbeat;

  const MqttState({
    this.isConnected = false,
    this.isConnecting = false,
    this.needsLogin = false,
    this.error,
    this.lamp = false,
    this.strip = false,
    this.fan = false,
    this.security = false,
    this.led = false,
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.gas = 0,
    this.motion = false,
    this.gatewayOnline = false,
    this.isPaired = false,
    this.lastHeartbeat,
  });

  MqttState copyWith({
    bool? isConnected,
    bool? isConnecting,
    bool? needsLogin,
    String? error,
    bool? lamp,
    bool? strip,
    bool? fan,
    bool? security,
    bool? led,
    double? temperature,
    double? humidity,
    int? gas,
    bool? motion,
    bool? gatewayOnline,
    bool? isPaired,
    DateTime? lastHeartbeat,
  }) {
    return MqttState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      needsLogin: needsLogin ?? this.needsLogin,
      error: error ?? this.error,
      lamp: lamp ?? this.lamp,
      strip: strip ?? this.strip,
      fan: fan ?? this.fan,
      security: security ?? this.security,
      led: led ?? this.led,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      gas: gas ?? this.gas,
      motion: motion ?? this.motion,
      gatewayOnline: gatewayOnline ?? this.gatewayOnline,
      isPaired: isPaired ?? this.isPaired,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }
}
