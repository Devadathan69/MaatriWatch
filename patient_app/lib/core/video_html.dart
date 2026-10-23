import 'dart:convert';

String videoHtml(String url, String token) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.host.endsWith('.daily.co') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Unverified private video room');
  }
  final params =
      jsonEncode({'url': url, 'token': token}).replaceAll('<', r'\u003c');
  return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><style>html,body{margin:0;width:100%;height:100%;background:#FFF9F1;font:16px sans-serif}#error{padding:24px}</style></head><body><div id="error" role="alert"></div>
<script crossorigin src="https://unpkg.com/@daily-co/daily-js@0.94.0"></script>
<script>
const error=document.getElementById('error');
try {
 const frame=DailyIframe.createFrame(document.body,{showLeaveButton:true,iframeStyle:{width:'100%',height:'100%',border:'0'}});
 frame.on('error',()=>{error.textContent='Video could not connect. Check camera/microphone permissions or contact your care team.';});
 frame.on('left-meeting',()=>{frame.destroy();error.textContent='You have left the consultation. You can close this screen.';});
 frame.join($params).catch(()=>{error.textContent='Video could not connect. Check your connection and camera/microphone permissions, then try again.';});
} catch (_) {error.textContent='Video could not load. Please check your connection and try again.';}
</script></body></html>''';
}
