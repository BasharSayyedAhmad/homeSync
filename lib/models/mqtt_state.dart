class MqttState {
  final bool isConnected;
  final bool isConnecting;
  final String? error;

  // حالات الأجهزة
  final bool lamp;
  final bool led;
  final bool strip;
  final bool fan;
  final bool security;
  final bool motion;
  final double temperature;
  final double humidity;
  final int gas;

  // حالات إضافية
  final bool gatewayOnline;
  final bool isPaired;
  final DateTime? lastHeartbeat;

  const MqttState({
    this.isConnected = false,
    this.isConnecting = false,
    this.error,
    this.lamp = false,
    this.led = false,
    this.strip = false,
    this.fan = false,
    this.security = false,
    this.motion = false,
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.gas = 0,
    this.gatewayOnline = false,
    this.isPaired = false,
    this.lastHeartbeat,
  });

  MqttState copyWith({
    bool? isConnected,
    bool? isConnecting,
    String? error,
    bool? lamp,
    bool? led,
    bool? strip,
    bool? fan,
    bool? security,
    bool? motion,
    double? temperature,
    double? humidity,
    int? gas,
    bool? gatewayOnline,
    bool? isPaired,
    DateTime? lastHeartbeat,
  }) {
    return MqttState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
      lamp: lamp ?? this.lamp,
      led: led ?? this.led,
      strip: strip ?? this.strip,
      fan: fan ?? this.fan,
      security: security ?? this.security,
      motion: motion ?? this.motion,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      gas: gas ?? this.gas,
      gatewayOnline: gatewayOnline ?? this.gatewayOnline,
      isPaired: isPaired ?? this.isPaired,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }
}
