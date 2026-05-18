import 'package:flutter/material.dart';
import 'package:homesync/knx/text_knx.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speech Test',
      home: TestKnx(),
    );
  }
}

class SpeechTestPage extends StatefulWidget {
  const SpeechTestPage({super.key});
  @override
  _SpeechTestPageState createState() => _SpeechTestPageState();
}

class _SpeechTestPageState extends State<SpeechTestPage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = "اضغط زر المايك وبلّش احكي";

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        print("STATUS: $status");
        if (status == "done") {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        print("ERROR: $error");
      },
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ar-SY",
        onResult: (result) {
          setState(() {
            _text = result.recognizedWords;
          });
        },
      );
    } else {
      setState(() => _isListening = false);
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Speech To Text Test")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(_text, style: TextStyle(fontSize: 22)),
            const SizedBox(height: 30),
            FloatingActionButton(
              onPressed: _isListening ? _stopListening : _startListening,
              child: Icon(_isListening ? Icons.mic : Icons.mic_none),
            ),
          ],
        ),
      ),
    );
  }
}
