import 'dart:ui_web' as ui;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'video_html.dart';

class VideoCallFrame extends StatefulWidget {
  const VideoCallFrame({super.key, required this.url, required this.token});
  final String url, token;
  @override
  State<VideoCallFrame> createState() => _VideoCallFrameState();
}

class _VideoCallFrameState extends State<VideoCallFrame> {
  late final String _type;
  web.HTMLIFrameElement? _frame;
  static int _counter = 0;
  @override
  void initState() {
    super.initState();
    _type = 'maatri-video-${_counter++}';
    ui.platformViewRegistry.registerViewFactory(_type, (id) {
      final frame = web.HTMLIFrameElement()
        ..srcdoc = videoHtml(widget.url, widget.token).toJS
        ..allow = 'camera; microphone; fullscreen; autoplay'
        ..referrerPolicy = 'no-referrer';
      frame.style
        ..width = '100%'
        ..height = '100%'
        ..border = '0';
      _frame = frame;
      return frame;
    });
  }

  @override
  void dispose() {
    _frame?.src = 'about:blank';
    _frame?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _type);
}
