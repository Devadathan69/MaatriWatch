import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Short in-memory PCM recording; no audio file is written to patient storage.
class ConcernRecorder {
  final _recorder = AudioRecorder();
  final _bytes = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _stream;
  Timer? _limit;
  int _size = 0;
  Future<void> start(void Function() onLimit) async {
    if (!await _recorder.hasPermission()) {
      throw StateError(
          'Microphone access was not allowed. You can enter symptoms manually instead.');
    }
    final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
    _stream = stream.listen((chunk) {
      if (_size + chunk.length <= 2800000) {
        _bytes.add(chunk);
        _size += chunk.length;
      } else {
        onLimit();
      }
    }, onError: (_) => onLimit());
    _limit = Timer(const Duration(seconds: 80), onLimit);
  }

  Future<Uint8List> stop() async {
    _limit?.cancel();
    await _recorder.stop();
    await _stream?.cancel();
    return wavBytes(_bytes.takeBytes());
  }

  Future<void> dispose() async {
    _limit?.cancel();
    await _stream?.cancel();
    await _recorder.dispose();
  }
}

Uint8List wavBytes(Uint8List pcm) {
  final output = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(output);
  void label(int start, String text) =>
      output.setRange(start, start + text.length, text.codeUnits);
  label(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  label(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  output.setRange(44, output.length, pcm);
  return output;
}
