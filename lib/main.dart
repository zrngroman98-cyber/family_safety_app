import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Safety Starter',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool locationEnabled = false;
  bool audioEnabled = false;
  bool loggingActive = false;
  List<Map<String, dynamic>> events = [];
  FlutterSoundRecorder? _recorder;
  bool _recorderInitialized = false;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    initRecorder();
    loadEvents();
  }

  Future<void> initRecorder() async {
    await _recorder!.openRecorder();
    _recorderInitialized = true;
  }

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/events.json');
  }

  Future<void> loadEvents() async {
    try {
      final f = await _localFile;
      if (await f.exists()) {
        final s = await f.readAsString();
        final jsonList = jsonDecode(s) as List<dynamic>;
        events = jsonList.map((e) => e as Map<String, dynamic>).toList();
        setState(() {});
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> saveEvent(Map<String, dynamic> ev) async {
    events.add(ev);
    final f = await _localFile;
    await f.writeAsString(jsonEncode(events));
    setState(() {});
  }

  Future<void> requestPermissions() async {
    await Permission.locationWhenInUse.request();
    await Permission.microphone.request();
    // For background location on Android, request locationAlways when appropriate
  }

  Future<void> captureLocationNow() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final ev = {
        'type': 'location',
        'lat': pos.latitude,
        'lon': pos.longitude,
        'time': DateTime.now().toIso8601String(),
        'accuracy': pos.accuracy
      };
      await saveEvent(ev);
    } catch (e) {
      print('loc err: $e');
    }
  }

  Future<void> startRecordingClip() async {
    if (!_recorderInitialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'clip_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '${dir.path}/$filename';
    await _recorder!.startRecorder(toFile: path, codec: Codec.aacMP4);
    // Stop automatically after 30 seconds for demo (adjust as needed)
    Future.delayed(Duration(seconds: 30), () async {
      if (_recorder!.isRecording) {
        final filePath = await _recorder!.stopRecorder();
        final ev = {
          'type': 'audio',
          'path': filePath,
          'time': DateTime.now().toIso8601String()
        };
        await saveEvent(ev);
      }
    });
  }

  Future<void> stopRecording() async {
    if (!_recorderInitialized) return;
    if (_recorder!.isRecording) {
      final filePath = await _recorder!.stopRecorder();
      final ev = {
        'type': 'audio',
        'path': filePath,
        'time': DateTime.now().toIso8601String()
      };
      await saveEvent(ev);
    }
  }

  Widget buildEventTile(Map<String, dynamic> e) {
    if (e['type'] == 'location') {
      return ListTile(
        leading: Icon(Icons.location_on),
        title: Text('${e['lat']}, ${e['lon']}'),
        subtitle: Text(e['time']),
      );
    } else {
      return ListTile(
        leading: Icon(Icons.mic),
        title: Text('Audio clip'),
        subtitle: Text(e['time']),
        trailing: IconButton(
          icon: Icon(Icons.play_arrow),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Play not implemented in starter')));
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Family Safety Starter')),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              title: Text('Enable Location Logging (consent)'),
              value: locationEnabled,
              onChanged: (v) async {
                if (v) await requestPermissions();
                setState(() => locationEnabled = v);
              },
            ),
            SwitchListTile(
              title: Text('Enable Audio Recording (consent)'),
              value: audioEnabled,
              onChanged: (v) async {
                if (v) await requestPermissions();
                setState(() => audioEnabled = v);
              },
            ),
            SizedBox(height: 8),
            ElevatedButton(
              child: Text(loggingActive ? 'Stop Logging' : 'Start Logging (foreground demo)'),
              onPressed: () async {
                if (!loggingActive) {
                  loggingActive = true;
                  setState(() {});
                  await captureLocationNow();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo logging started — not a full background service')));
                } else {
                  loggingActive = false;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo logging stopped')));
                }
              },
            ),
            SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: audioEnabled ? () => startRecordingClip() : null,
                  child: Text('Record 30s Clip'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: audioEnabled ? () => stopRecording() : null,
                  child: Text('Stop Recording'),
                ),
              ],
            ),
            SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, i) => buildEventTile(events[i]),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    super.dispose();
  }
}
