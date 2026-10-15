import 'package:example/speedometer.dart';
import 'package:flutter/material.dart';
import 'package:speed_test_dart/classes/classes.dart';
import 'package:speed_test_dart/speed_test_dart.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SpeedTestDart tester = SpeedTestDart();
  List<Server> bestServersList = [];

  double downloadRate = 0;
  double uploadRate = 0;

  bool readyToTest = false;
  bool loadingDownload = false;
  bool loadingUpload = false;

  Future<void> setBestServers() async {
    final settings = await tester.getSettings();
    final servers = settings.servers;

    final _bestServersList = await tester.getBestServers(
      servers: servers,
    );

    setState(() {
      bestServersList = _bestServersList;
      readyToTest = true;
    });
  }

  void _showSpeed(void Function() update) {
    if (!mounted) return;
    setState(update);
  }

  Future<void> _testDownloadSpeed() async {
    setState(() {
      loadingDownload = true;
      downloadRate = 0;
    });
    final rate = await tester.testDownloadSpeed(
      servers: bestServersList,
      onProgress: (mbps) => _showSpeed(() => downloadRate = mbps),
    );
    _showSpeed(() {
      downloadRate = rate;
      loadingDownload = false;
    });
  }

  Future<void> _testUploadSpeed() async {
    setState(() {
      loadingUpload = true;
      uploadRate = 0;
    });

    final rate = await tester.testUploadSpeed(
      servers: bestServersList,
      onProgress: (mbps) => _showSpeed(() => uploadRate = mbps),
    );

    _showSpeed(() {
      uploadRate = rate;
      loadingUpload = false;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setBestServers();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Speed Test Example App'),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Download Test:',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                Speedometer(mbps: downloadRate),
                Text(
                  loadingDownload
                      ? 'Testing download...'
                      : 'Final ${downloadRate.toStringAsFixed(2)} Mb/s',
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: readyToTest && !loadingDownload
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  onPressed: loadingDownload
                      ? null
                      : () async {
                          if (!readyToTest || bestServersList.isEmpty) return;
                          await _testDownloadSpeed();
                        },
                  child: const Text('Start'),
                ),
                const SizedBox(
                  height: 50,
                ),
                const Text(
                  'Upload Test:',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                Speedometer(mbps: uploadRate),
                Text(
                  loadingUpload
                      ? 'Testing upload...'
                      : 'Final ${uploadRate.toStringAsFixed(2)} Mb/s',
                ),
                const SizedBox(
                  height: 10,
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: readyToTest ? Colors.blue : Colors.grey,
                  ),
                  onPressed: loadingUpload
                      ? null
                      : () async {
                          if (!readyToTest || bestServersList.isEmpty) return;
                          await _testUploadSpeed();
                        },
                  child: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
