import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'video_html.dart';

class VideoCallFrame extends StatefulWidget {
  const VideoCallFrame({super.key, required this.url, required this.token});
  final String url, token;
  @override
  State<VideoCallFrame> createState() => _VideoCallFrameState();
}

class _VideoCallFrameState extends State<VideoCallFrame> {
  WebViewController? _controller;
  String? _error;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _error = 'Use the web or Android app for video calls.');
      return;
    }
    final permissions =
        await [Permission.camera, Permission.microphone].request();
    if (!mounted) return;
    if (permissions.values.any((status) => !status.isGranted)) {
      setState(() => _error =
          'Camera and microphone access are needed for a video visit. You can leave and contact your care team instead.');
      return;
    }
    final controller = WebViewController(onPermissionRequest: (request) {
      if (request.types.every((type) =>
          type == WebViewPermissionResourceType.camera ||
          type == WebViewPermissionResourceType.microphone)) {
        request.grant();
      } else {
        request.deny();
      }
    })
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
          NavigationDelegate(onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        return request.url == 'about:blank' ||
                (uri?.scheme == 'https' &&
                    (uri!.host.endsWith('.daily.co') ||
                        uri.host == 'unpkg.com'))
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      }));
    await controller.loadHtmlString(videoHtml(widget.url, widget.token),
        baseUrl: widget.url);
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
      : _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!);
}
