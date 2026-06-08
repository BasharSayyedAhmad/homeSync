import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/hive_service.dart';
import 'core/services/secure_storage_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Hive
  await HiveService.init();

  // التحقق من وجود جلسة سابقة
  final hasSession = HiveService.hasValidSession();

  // التحقق من وجود بيانات MQTT في Secure Storage
  final hasCredentials = await SecureStorageService.hasCredentials();

  runApp(ProviderScope(child: MyApp(hasSession: hasSession && hasCredentials)));
}

class MyApp extends StatelessWidget {
  final bool hasSession;

  const MyApp({super.key, required this.hasSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: hasSession ? const HomeScreen() : const LoginScreen(),
    );
  }
}
