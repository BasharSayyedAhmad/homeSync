class VoiceState {
  final bool isListening;
  final String recognizedText;
  final String feedback;

  const VoiceState({
    this.isListening = false,
    this.recognizedText = '',
    this.feedback = '',
  });

  VoiceState copyWith({
    bool? isListening,
    String? recognizedText,
    String? feedback,
  }) {
    return VoiceState(
      isListening: isListening ?? this.isListening,
      recognizedText: recognizedText ?? this.recognizedText,
      feedback: feedback ?? this.feedback,
    );
  }
}
