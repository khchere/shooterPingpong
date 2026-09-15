// 웹용: 브라우저의 SpeechRecognition(webkitSpeechRecognition) 호출
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('webkitSpeechRecognition')
extension type _SpeechRecognition._(JSObject _) implements JSObject {
  external factory _SpeechRecognition();
  external set lang(String v);
  external set interimResults(bool v);
  external set maxAlternatives(int v);
  external set continuous(bool v);
  external set onresult(JSFunction f);
  external set onerror(JSFunction f);
  external set onend(JSFunction f);
  external void start();
  external void stop();
  external void abort();
}

bool get isSupported =>
    globalContext.has('webkitSpeechRecognition') ||
    globalContext.has('SpeechRecognition');

_SpeechRecognition? _active;

Future<List<String>> listen() {
  final completer = Completer<List<String>>();
  final rec = _SpeechRecognition()
    ..lang = 'ko-KR'
    ..interimResults = false
    ..maxAlternatives = 5
    ..continuous = false;
  _active = rec;

  void finish(List<String> result) {
    if (!completer.isCompleted) completer.complete(result);
    if (_active == rec) _active = null;
  }

  rec.onresult = ((JSObject event) {
    final alternatives = <String>[];
    try {
      // event.results[0][i].transcript
      final results = event.getProperty<JSObject>('results'.toJS);
      final first = results.getProperty<JSObject>(0.toJS);
      final n = first.getProperty<JSNumber>('length'.toJS).toDartInt;
      for (var i = 0; i < n; i++) {
        final alt = first.getProperty<JSObject>(i.toJS);
        final text = alt.getProperty<JSString>('transcript'.toJS).toDart;
        if (text.trim().isNotEmpty) alternatives.add(text.trim());
      }
    } catch (_) {}
    finish(alternatives);
  }).toJS;
  rec.onerror = ((JSObject _) => finish([])).toJS;
  rec.onend = ((JSObject _) => finish([])).toJS;

  try {
    rec.start();
  } catch (_) {
    finish([]);
  }
  return completer.future;
}

void stop() {
  try {
    _active?.stop();
  } catch (_) {}
}
