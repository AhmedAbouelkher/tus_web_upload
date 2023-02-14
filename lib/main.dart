// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tus_client_dart/tus_client_dart.dart';

import '.env.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final VideoTusController _uploadController;
  XFile? _file;

  @override
  void initState() {
    _uploadController = VideoTusController();
    _uploadController.streamController.stream.listen(_listener);
    super.initState();
  }

  @override
  void dispose() {
    _uploadController.dispose();
    super.dispose();
  }

  void _listener(progress) {
    if (progress == null) {
      debugPrint("Upload complete");
    } else {
      debugPrint("Upload progress: $progress");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUS App',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('TUS APP'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    allowMultiple: false,
                    type: FileType.video,
                  );
                  if (result != null) {
                    final p = result.files.first.bytes;
                    if (p == null) {
                      debugPrint("No file selected");
                      return;
                    }
                    XFile file = XFile.fromData(
                      p,
                      name: result.files.first.name,
                      mimeType: result.files.first.extension,
                    );
                    setState(() {
                      _file = file;
                    });
                  }
                },
                child: const Text('PICK FILE'),
              ),
              if (_file != null) ...[
                const SizedBox(height: 20),
                Text(
                  'File Name: ${_file!.name}',
                  style: const TextStyle(fontSize: 20),
                ),
              ],
              const SizedBox(height: 50),
              Builder(builder: (context) {
                return TextButton(
                  onPressed: () async {
                    if (_file == null) {
                      debugPrint("No file selected");
                      return;
                    }
                    try {
                      await _uploadController.upload(
                        _file!,
                        title: _file!.name,
                      );
                      await _uploadController.done;
                      setState(() {
                        _file = null;
                      });
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text("Upload complete"),
                          ),
                        );
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Upload failed"),
                                Text(e.toString()),
                              ],
                            ),
                            duration: const Duration(seconds: 10),
                          ),
                        );
                    }
                  },
                  child: const Text("Upload File"),
                );
              })
            ],
          ),
        ),
      ),
    );
  }
}

class VideoTusController extends ChangeNotifier {
  final StreamController<double?> _streamController;
  late Completer<void> _completer;

  TusClient? _client;

  StreamController<double?> get streamController => _streamController;

  VideoTusController()
      : _streamController = StreamController.broadcast(),
        _completer = Completer();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  Future<void> upload(XFile video, {String? title}) async {
    if (_isUploading) return;
    _isUploading = true;
    notifyListeners();

    _client = TusClient(video, store: TusMemoryStore());

    await _uploadOrResume();
  }

  bool _isCanceling = false;

  Future<void> cancelUpload() async {
    if (_isCanceling) return;
    _isCanceling = true;
    try {
      await _client?.cancelUpload();
      _client = null;
      clear();
    } finally {
      _isCanceling = false;
    }
  }

  Future<void> get done => _completer.future;

  Future<void> _uploadOrResume() async {
    try {
      _streamController.add(0.01);
      await _client?.upload(
        uri: Uri.parse("https://api.omegastream.net/company/client/video/stream"),
        headers: {
          "Authorization": "Bearer $apiKey",
        },
        onComplete: () {
          debugPrint("Upload complete");
          _streamController.add(null);

          _completer = Completer();
          _completer.complete();
        },
        onProgress: (progress, _) {
          _streamController.add(progress);
        },
      );
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  void clear() {
    _streamController.add(null);
    _completer = Completer();
    notifyListeners();
  }

  @override
  void dispose() {
    _streamController.close();
    _client = null;
    super.dispose();
  }
}
