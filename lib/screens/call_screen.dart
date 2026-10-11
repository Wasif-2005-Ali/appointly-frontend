import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class CallScreen extends StatefulWidget {
  final String callerId;
  const CallScreen({Key? key, required this.callerId}) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  late WebSocketChannel _channel;

  @override
  void initState() {
    super.initState();
    initRenderers();
    _connectWebSocket();
  }

  // 1. Renderers Initialize karna
  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _getUserMedia();
  }

  // 2. Camera aur Mic ko on karna
  Future<void> _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      }
    };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    setState(() {
      _localRenderer.srcObject = stream;
      _localStream = stream;
    });
  }

  // 3. Django WebSockets se connect karna (Signaling)
  void _connectWebSocket() {
    // Apna laptop ka IP address lagayen (e.g., 192.168.1.5)
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://192.168.1.5:8000/ws/call/'),
    );

    _channel.stream.listen((message) {
      var data = jsonDecode(message);
      print("Message received: $data");
      // Yahan hum SDP Offers aur ICE Candidates receive karke handle karenge
    });
  }

  // Call End karne par memory free karna
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video (Doosre user ki video poori screen par)
          Positioned.fill(
            child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),

          // Local Video (Apni video choti si corner mein)
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              width: 100,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
          ),

          // End Call Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: () {
                  Navigator.pop(context); // Call end karke wapas pichli screen par
                },
                child: const Icon(Icons.call_end, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}