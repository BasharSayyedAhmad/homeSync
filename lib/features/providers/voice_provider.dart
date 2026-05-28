import 'package:homesync/models/voice_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:homesync/features/providers/mqtt_provider.dart';
import 'package:homesync/core/constant/voice_command.dart';

part 'voice_provider.g.dart';

@riverpod
class VoiceNotifier extends _$VoiceNotifier {
  late stt.SpeechToText _speech;

  @override
  VoiceState build() {
    _speech = stt.SpeechToText();
    return const VoiceState();
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == "done" || status == "notListening") {
          state = state.copyWith(isListening: false);
        }
      },
      onError: (error) {
        state = state.copyWith(
          isListening: false,
          feedback: 'خطأ في المايك: $error',
        );
      },
    );

    if (available) {
      state = state.copyWith(
        isListening: true,
        feedback: '🎤 جاري الاستماع...',
        recognizedText: '',
      );

      _speech.listen(
        localeId: "ar-SY",
        listenFor: const Duration(seconds: 5),
        onResult: (result) {
          final command = result.recognizedWords;
          state = state.copyWith(recognizedText: command);
          _handleVoiceCommand(command);

          if (result.finalResult) {
            stopListening();
          }
        },
      );
    } else {
      state = state.copyWith(feedback: '❌ المايك غير متوفر');
    }
  }

  void _handleVoiceCommand(String text) {
    text = text.trim().toLowerCase();
    String? resultMessage;

    // لمبة
    if (lightOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_ON");
      resultMessage = "✅ تم تشغيل اللمبة";
    } else if (lightOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_OFF");
      resultMessage = "✅ تم إطفاء اللمبة";
    }
    // مروحة
    else if (fanOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("FAN_ON");
      resultMessage = "✅ تم تشغيل المروحة";
    } else if (fanOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("FAN_OFF");
      resultMessage = "✅ تم إطفاء المروحة";
    }
    // Strip
    else if (stripOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("STRIP_ON");
      resultMessage = "✅ تم تشغيل الـ Strip";
    } else if (stripOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("STRIP_OFF");
      resultMessage = "✅ تم إطفاء الـ Strip";
    }
    // أمان
    else if (text.contains("شغل الأمان") || text.contains("فعل الأمان")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SECURITY_ON");
      resultMessage = "✅ تم تفعيل نظام الأمان";
    } else if (text.contains("طفي الأمان") || text.contains("وقف الأمان")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SECURITY_OFF");
      resultMessage = "✅ تم إيقاف نظام الأمان";
    } else if (text.isNotEmpty) {
      resultMessage = "❌ أمر غير معروف: '$text'";
    }

    if (resultMessage != null) {
      state = state.copyWith(feedback: resultMessage);
      Future.delayed(const Duration(seconds: 3), () {
        if (state.feedback == resultMessage) {
          state = state.copyWith(feedback: '');
        }
      });
    }
  }

  void stopListening() {
    if (_speech.isListening) {
      _speech.stop();
    }
    state = state.copyWith(isListening: false);
  }

  void clearFeedback() {
    state = state.copyWith(feedback: '');
  }
}
