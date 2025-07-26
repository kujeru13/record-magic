
// === main.dart ===
// Flutter app to record video, upload to backend, and display album names with Discogs links and images

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(VinylApp(camera: firstCamera));
}

class VinylApp extends StatelessWidget {
  final CameraDescription camera;
  const VinylApp({required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: VinylRecorder(camera: camera),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VinylRecorder extends StatefulWidget {
  final CameraDescription camera;
  const VinylRecorder({required this.camera});

  @override
  _VinylRecorderState createState() => _VinylRecorderState();
}

class _VinylRecorderState extends State<VinylRecorder> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool isRecording = false;
  List<Map<String, dynamic>> albums = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> startRecording() async {
    try {
      await _initializeControllerFuture;
      await _controller.startVideoRecording();
      setState(() => isRecording = true);
    } catch (e) {
      print(e);
    }
  }

  Future<void> stopRecording() async {
    try {
      final file = await _controller.stopVideoRecording();
      setState(() => isRecording = false);
      await sendVideoToBackend(File(file.path));
    } catch (e) {
      print(e);
    }
  }

  Future<void> sendVideoToBackend(File videoFile) async {
    setState(() => loading = true);
    final uri = Uri.parse("http://10.0.2.2:8000/identify");
    final request = http.MultipartRequest("POST", uri)
      ..files.add(await http.MultipartFile.fromPath("video", videoFile.path));
    final response = await request.send();

    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      final data = jsonDecode(responseBody);
      final List<Map<String, dynamic>> parsed = (data['albums'] as List).map((item) => {
        'album': item['album'],
        'discogs_url': item['discogs']?['discogs_url'],
        'thumb': item['discogs']?['thumb']
      }).toList();
      setState(() => albums = parsed);
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🎵 Vinyl Identifier')),
      body: Column(
        children: [
          FutureBuilder(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: CameraPreview(_controller),
                );
              } else {
                return Center(child: CircularProgressIndicator());
              }
            },
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: isRecording ? stopRecording : startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : Colors.green,
            ),
            child: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: CircularProgressIndicator(),
            ),
          if (albums.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return ListTile(
                    leading: album['thumb'] != null
                        ? Image.network(album['thumb'], width: 50, height: 50, fit: BoxFit.cover)
                        : Icon(Icons.album),
                    title: Text(album['album']),
                    subtitle: album['discogs_url'] != null
                        ? Text(album['discogs_url'], style: TextStyle(color: Colors.blue))
                        : null,
                    onTap: album['discogs_url'] != null
                        ? () => launchURL(album['discogs_url'])
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }
  }
}
