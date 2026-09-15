// 웹이 아닌 플랫폼용 (음성 인식 미지원)
bool get isSupported => false;

Future<List<String>> listen() async => [];

void stop() {}
