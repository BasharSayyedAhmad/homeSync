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
  // ✅ AC State (جديد)
  final bool acPower;
  final String acMode; // "cool", "heat", "dry", "off"
  final int acTemp; // 18-29
  final int acFan; // 1, 2, 3
  final bool acSwing;
  final bool acAutoMode;
  final String acSeason; // "summer", "winter"

  // ✅ Door & Garage (جديد)
  final bool doorOpen;
  final bool garageOpen;

  // ✅ Gas Alert (جديد)
  final String gasLevel; // "OK", "WARN", "ALERT"

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
    // ✅ AC defaults
    this.acPower = false,
    this.acMode = 'off',
    this.acTemp = 24,
    this.acFan = 2,
    this.acSwing = false,
    this.acAutoMode = false,
    this.acSeason = 'summer',

    // ✅ Door/Garage defaults
    this.doorOpen = false,
    this.garageOpen = false,

    // ✅ Gas defaults
    this.gasLevel = 'OK',
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

    // ✅ AC copyWith
    bool? acPower,
    String? acMode,
    int? acTemp,
    int? acFan,
    bool? acSwing,
    bool? acAutoMode,
    String? acSeason,

    // ✅ Door/Garage copyWith
    bool? doorOpen,
    bool? garageOpen,

    // ✅ Gas copyWith
    String? gasLevel,
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

      // ✅ AC
      acPower: acPower ?? this.acPower,
      acMode: acMode ?? this.acMode,
      acTemp: acTemp ?? this.acTemp,
      acFan: acFan ?? this.acFan,
      acSwing: acSwing ?? this.acSwing,
      acAutoMode: acAutoMode ?? this.acAutoMode,
      acSeason: acSeason ?? this.acSeason,

      // ✅ Door/Garage
      doorOpen: doorOpen ?? this.doorOpen,
      garageOpen: garageOpen ?? this.garageOpen,

      // ✅ Gas
      gasLevel: gasLevel ?? this.gasLevel,
    );
  }
}
