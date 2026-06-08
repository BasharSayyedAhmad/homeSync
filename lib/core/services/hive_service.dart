import 'package:hive_flutter/hive_flutter.dart';

class UserSession {
  final String username;
  final bool isLoggedIn;
  final DateTime loginTime;
  final DateTime? sessionExpiry;

  UserSession({
    required this.username,
    required this.isLoggedIn,
    required this.loginTime,
    this.sessionExpiry,
  });

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'isLoggedIn': isLoggedIn,
      'loginTime': loginTime.toIso8601String(),
      'sessionExpiry': sessionExpiry?.toIso8601String(),
    };
  }

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      username: map['username'],
      isLoggedIn: map['isLoggedIn'],
      loginTime: DateTime.parse(map['loginTime']),
      sessionExpiry: map['sessionExpiry'] != null
          ? DateTime.parse(map['sessionExpiry'])
          : null,
    );
  }

  bool get isSessionValid {
    if (sessionExpiry == null) return true;
    return DateTime.now().isBefore(sessionExpiry!);
  }
}

class HiveService {
  static const String _sessionBox = 'session_box';
  static const String _sessionKey = 'current_session';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_sessionBox);
  }

  static Box get _box => Hive.box(_sessionBox);

  // حفظ الجلسة
  static Future<void> saveSession(UserSession session) async {
    await _box.put(_sessionKey, session.toMap());
  }

  // استرجاع الجلسة
  static UserSession? getSession() {
    final map = _box.get(_sessionKey);
    if (map == null) return null;
    return UserSession.fromMap(Map<String, dynamic>.from(map));
  }

  // التحقق من وجود جلسة صالحة
  static bool hasValidSession() {
    final session = getSession();
    if (session == null || !session.isLoggedIn) return false;
    return session.isSessionValid;
  }

  // تسجيل خروج
  static Future<void> clearSession() async {
    await _box.delete(_sessionKey);
  }
}
