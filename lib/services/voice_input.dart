// 브라우저 내장 음성 인식(Web Speech API)으로 한 문장을 받아온다.
// 웹이 아닌 플랫폼에서는 [VoiceInput.isSupported]가 false.
import 'voice_input_stub.dart'
    if (dart.library.js_interop) 'voice_input_web.dart' as impl;

class VoiceInput {
  static bool get isSupported => impl.isSupported;

  /// 마이크로 한 문장을 듣고 인식 후보 문자열들을 돌려준다 (정확도 높은 순).
  /// 인식 실패·취소 시 빈 목록.
  static Future<List<String>> listen() => impl.listen();

  /// 듣는 중이면 중단
  static void stop() => impl.stop();
}
