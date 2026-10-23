import 'package:flutter/material.dart';

class VideoCallFrame extends StatelessWidget {
  const VideoCallFrame({super.key, required this.url, required this.token});
  final String url, token;
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('Video calls are supported in the web and Android apps.'));
}
