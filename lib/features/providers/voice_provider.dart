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

    // ✅ LED Strip
    if (text.contains("شغل الضوء") ||
        text.contains("شغل اللمبة") ||
        text.contains("ضوء on")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_ON");
      resultMessage = "✅ تم تشغيل الضوء";
    } else if (text.contains("اطفئ الضوء") ||
        text.contains("طفي الضوء") ||
        text.contains("ضوء off")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_OFF");
      resultMessage = "✅ تم إطفاء الضوء";
    } else if (text.contains("ضوء أبيض") || text.contains("أبيض")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_WHITE");
      resultMessage = "✅ تم تغيير الضوء للأبيض";
    } else if (text.contains("ضوء أحمر") || text.contains("أحمر")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_RED");
      resultMessage = "✅ تم تغيير الضوء للأحمر";
    } else if (text.contains("زود السطوع") || text.contains("أقوى")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_DIM_UP");
      resultMessage = "✅ تم زيادة السطوع";
    } else if (text.contains("قلل السطوع") || text.contains("أخفف")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_DIM_DOWN");
      resultMessage = "✅ تم تقليل السطوع";
    } else if (text.contains("إنذار") || text.contains("طوارئ")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LED_FLASH");
      resultMessage = "🚨 تم تفعيل الإنذار";
    }
    // ✅ Lamp (القديم)
    else if (lightOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LAMP_ON");
      resultMessage = "✅ تم تشغيل المصباح";
    } else if (lightOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("LAMP_OFF");
      resultMessage = "✅ تم إطفاء المصباح";
    }
    // ✅ Fan (القديم)
    else if (fanOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("FAN_ON");
      resultMessage = "✅ تم تشغيل المروحة";
    } else if (fanOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("FAN_OFF");
      resultMessage = "✅ تم إطفاء المروحة";
    }
    // ✅ Strip (القديم)
    else if (stripOnCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("STRIP_ON");
      resultMessage = "✅ تم تشغيل الـ Strip";
    } else if (stripOffCommands.any((cmd) => text.contains(cmd))) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("STRIP_OFF");
      resultMessage = "✅ تم إطفاء الـ Strip";
    }
    // ✅ Security (القديم)
    else if (text.contains("شغل الأمان") || text.contains("فعل الأمان")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SECURITY_ON");
      resultMessage = "✅ تم تفعيل نظام الأمان";
    } else if (text.contains("طفي الأمان") || text.contains("وقف الأمان")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SECURITY_OFF");
      resultMessage = "✅ تم إيقاف نظام الأمان";
    }
    // ✅ AC — جديد
    else if (text.contains("شغل المكيف") ||
        text.contains("تشغيل المكيف") ||
        text.contains("مكيف on")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_ON");
      resultMessage = "✅ تم تشغيل المكيف";
    } else if (text.contains("اطفئ المكيف") ||
        text.contains("طفي المكيف") ||
        text.contains("مكيف off")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_OFF");
      resultMessage = "✅ تم إطفاء المكيف";
    } else if (text.contains("تبريد") || text.contains("برد")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_MODE_COOL");
      resultMessage = "❄️ تم تفعيل وضع التبريد";
    } else if (text.contains("تدفئة") ||
        text.contains("دفاية") ||
        text.contains("سخن")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_MODE_HEAT");
      resultMessage = "🔥 تم تفعيل وضع التدفئة";
    } else if (text.contains("تجفيف") || text.contains("رطوبة")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_MODE_DRY");
      resultMessage = "💧 تم تفعيل وضع التجفيف";
    } else if (text.contains("حرارة زيادة") ||
        text.contains("أحر") ||
        text.contains("زود الحرارة")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_TEMP_UP");
      resultMessage = "🌡️ تم رفع درجة الحرارة";
    } else if (text.contains("حرارة نقصان") ||
        text.contains("أبرد") ||
        text.contains("قلل الحرارة")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_TEMP_DOWN");
      resultMessage = "🌡️ تم خفض درجة الحرارة";
    } else if (text.contains("مروحة واحد") || text.contains("مروحة ضعيفة")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_FAN_1");
      resultMessage = "🌀 مروحة منخفضة";
    } else if (text.contains("مروحة اثنين") || text.contains("مروحة متوسطة")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_FAN_2");
      resultMessage = "🌀 مروحة متوسطة";
    } else if (text.contains("مروحة ثلاثة") || text.contains("مروحة قوية")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_FAN_3");
      resultMessage = "🌀 مروحة عالية";
    } else if (text.contains("سوينغ") || text.contains("تأرجح")) {
      ref.read(mqttNotifierProvider.notifier).sendAcCommand("AC_SWING_ON");
      resultMessage = "🔄 تم تفعيل السوينغ";
    }
    // ✅ Door — جديد
    else if (text.contains("افتح الباب") || text.contains("افتح الباب")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("DOOR_OPEN");
      resultMessage = "🚪 تم فتح الباب";
    } else if (text.contains("سكر الباب") ||
        text.contains("قفل الباب") ||
        text.contains("أغلق الباب")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("DOOR_CLOSE");
      resultMessage = "🚪 تم إغلاق الباب";
    }
    // ✅ Garage — جديد
    else if (text.contains("افتح المرآب") || text.contains("افتح الجراج")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("GARAGE_OPEN");
      resultMessage = "🚗 تم فتح المرآب";
    } else if (text.contains("سكر المرآب") ||
        text.contains("أغلق المرآب") ||
        text.contains("قفل المرآب")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("GARAGE_CLOSE");
      resultMessage = "🚗 تم إغلاق المرآب";
    }
    // ✅ Scenes — جديد
    else if (text.contains("وضع خروج") ||
        text.contains("خروج") ||
        text.contains("مغادرة")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SCENE_LEAVE");
      resultMessage = "🏠 وضع المغادرة";
    } else if (text.contains("وضع نوم") ||
        text.contains("نوم") ||
        text.contains("ليل")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SCENE_NIGHT");
      resultMessage = "🌙 وضع النوم";
    } else if (text.contains("وضع إنذار") ||
        text.contains("إنذار") ||
        text.contains("طوارئ")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SCENE_ALERT");
      resultMessage = "🚨 وضع الإنذار";
    } else if (text.contains("وضع ترحيب") ||
        text.contains("ترحيب") ||
        text.contains("رجوع")) {
      ref.read(mqttNotifierProvider.notifier).sendCommand("SCENE_WELCOME");
      resultMessage = "🏡 وضع الترحيب";
    }
    // ✅ Auto Mode — جديد
    else if (text.contains("وضع تلقائي") ||
        text.contains("تلقائي") ||
        text.contains("أوتو")) {
      ref.read(mqttNotifierProvider.notifier).sendAutoMode(true);
      resultMessage = "🤖 الوضع التلقائي مفعل";
    } else if (text.contains("وضع يدوي") ||
        text.contains("يدوي") ||
        text.contains("مانيوال")) {
      ref.read(mqttNotifierProvider.notifier).sendAutoMode(false);
      resultMessage = "👤 الوضع اليدوي مفعل";
    }
    // ✅ Season — جديد
    else if (text.contains("صيف") || text.contains("summer")) {
      ref.read(mqttNotifierProvider.notifier).sendSeason("summer");
      resultMessage = "☀️ الموسم: صيف";
    } else if (text.contains("شتاء") || text.contains("winter")) {
      ref.read(mqttNotifierProvider.notifier).sendSeason("winter");
      resultMessage = "❄️ الموسم: شتاء";
    }
    // ❌ Unknown command
    else if (text.isNotEmpty) {
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
