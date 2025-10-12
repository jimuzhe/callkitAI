import 'dart:convert';
import 'dart:typed_data';

import 'xiaozhi_protocol.dart';

typedef JsonHandler = void Function(Map<String, dynamic> msg);
typedef TextHandler = void Function(String text);

class XiaozhiDispatcher {
  final XiaozhiProtocol protocol;

  JsonHandler? onHello;
  JsonHandler? onTts;
  JsonHandler? onLlm;
  JsonHandler? onError;
  TextHandler? onStt;
  void Function(Uint8List bytes)? onBinaryAudio;
  JsonHandler? onJson; // generic JSON handler

  // finer-grained TTS callbacks
  JsonHandler? onTtsStart;
  JsonHandler? onTtsSentenceStart;
  JsonHandler? onTtsSentenceDelta;
  JsonHandler? onTtsSentenceEnd;
  JsonHandler? onTtsEnd;

  // finer-grained LLM callbacks
  JsonHandler? onLlmDelta;
  JsonHandler? onLlmEnd;

  XiaozhiDispatcher(this.protocol) {
    protocol.stream.listen(
      _onData,
      onError: (e) {
        onError?.call({'message': e.toString()});
      },
      onDone: () {
        // stream closed
      },
    );
  }

  void _onData(dynamic data) {
    try {
      if (data is String) {
        Map<String, dynamic>? msg;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>)
            msg = decoded.cast<String, dynamic>();
        } catch (_) {
          // not JSON
        }

        if (msg != null) {
          final type = msg['type'] is String ? msg['type'] as String : '';
          switch (type) {
            case 'hello':
              onHello?.call(msg);
              return;
            case 'tts':
              onTts?.call(msg);
              final state = (msg['state'] is String)
                  ? msg['state'] as String
                  : '';
              if (state == 'start') {
                onTtsStart?.call(msg);
              } else if (state == 'sentence_start') {
                onTtsSentenceStart?.call(msg);
              } else if (state == 'sentence_delta' ||
                  state == 'sentence_chunk' ||
                  state == 'chunk' ||
                  state == 'delta' ||
                  state == 'partial' ||
                  state == 'update') {
                onTtsSentenceDelta?.call(msg);
              } else if (state == 'sentence_end') {
                onTtsSentenceEnd?.call(msg);
              } else if (state == 'end' ||
                  state == 'stop' ||
                  state == 'finish' ||
                  state == 'finished') {
                onTtsEnd?.call(msg);
              }
              return;
            case 'llm':
              onLlm?.call(msg);
              final state = (msg['state'] is String)
                  ? msg['state'] as String
                  : '';
              if (state == 'end' ||
                  state == 'finish' ||
                  state == 'finished' ||
                  state == 'complete') {
                onLlmEnd?.call(msg);
              } else {
                onLlmDelta?.call(msg);
              }
              return;
            case 'stt':
              final text = msg['text'];
              if (text is String && text.isNotEmpty) onStt?.call(text);
              return;
            case 'error':
              onError?.call(msg);
              return;
            case 'audio':
              onJson?.call(msg);
              return;
            default:
              onJson?.call(msg);
              return;
          }
        }

        final txt = data.trim();
        if (txt.isNotEmpty) onStt?.call(txt);
      } else if (data is Uint8List) {
        onBinaryAudio?.call(data);
      }
    } catch (e) {
      onError?.call({'message': e.toString()});
    }
  }
}
