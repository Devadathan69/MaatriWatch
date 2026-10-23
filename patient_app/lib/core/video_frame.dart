export 'video_frame_stub.dart'
    if (dart.library.io) 'video_frame_native.dart'
    if (dart.library.js_interop) 'video_frame_web.dart';
