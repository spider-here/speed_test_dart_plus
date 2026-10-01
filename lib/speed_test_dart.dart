library speed_test_dart;

import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:speed_test_dart/classes/classes.dart';
import 'package:speed_test_dart/constants.dart';
import 'package:speed_test_dart/enums/file_size.dart';
import 'package:sync/sync.dart';
import 'package:xml/xml.dart';


/// A Speed tester.
class SpeedTestDart {
  /// Returns [Settings] from speedtest.net.

  static const _xmlHeaders = {
    'User-Agent':
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    'Accept': 'application/xml,text/xml,*/*',
  };

  static const _headers = {
    'User-Agent':
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',  };


  Future<Settings> getSettings() async {
    final response = await http.get(Uri.parse(configUrl),
    headers: _xmlHeaders);



    print('Speedtest config status: ${response.statusCode}');
    print(
      'Speedtest config content-type: '
          '${response.headers['content-type']}',
    );
    print(
      'Speedtest config body: '
          '${response.body.substring(
        0,
        response.body.length > 300 ? 300 : response.body.length,
      )}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Speedtest config request failed: '
            '${response.statusCode} ${response.body}',
      );
    }

    final settings = Settings.fromXMLElement(
      XmlDocument.parse(response.body).getElement('settings'),
    );

    var serversConfig = ServersList(<Server>[]);
    for (final element in serversUrls) {
      if (serversConfig.servers.isNotEmpty) break;
      try {
        final resp = await http.get(Uri.parse(element),
            headers: _xmlHeaders);

        serversConfig = ServersList.fromXMLElement(
          XmlDocument.parse(resp.body).getElement('settings'),
        );
      } catch (ex) {
        serversConfig = ServersList(<Server>[]);
      }
    }

    final ignoredIds = settings.serverConfig.ignoreIds.split(',');
    serversConfig.calculateDistances(settings.client.geoCoordinate);
    settings.servers = serversConfig.servers
        .where(
          (s) => !ignoredIds.contains(s.id.toString()),
        )
        .where(
          (s) => s.country.trim().toLowerCase() != 'india',
    )
        .toList();
    settings.servers.sort((a, b) => a.distance.compareTo(b.distance));

    return settings;
  }

  /// Returns a List[Server] with the best servers, ordered
  /// by lowest to highest latency.
  Future<List<Server>> getBestServers({
    required List<Server> servers,
    int retryCount = 2,
    int timeoutInSeconds = 2,
  }) async {
    final List<Server> serversToTest = [];

    for (final server in servers) {
      final latencyUri = createTestUrl(server, 'latency.txt');

      final stopwatch = Stopwatch()..start();

      try {
        final response = await http.get(
          latencyUri,
          headers: _headers,
        ).timeout(
          Duration(seconds: timeoutInSeconds),
        );

        stopwatch.stop();

        print(
          'Latency ${latencyUri.host}: '
              '${response.statusCode} '
              '${response.body.length} bytes '
              '${stopwatch.elapsedMilliseconds} ms',
        );

        if (response.statusCode != 200) {
          continue;
        }

        final latency = stopwatch.elapsedMilliseconds.toDouble();

        if (latency < 500) {
          server.latency = latency;
          serversToTest.add(server);
        }
      } catch (e) {
        stopwatch.stop();
        print('Latency error ${latencyUri.host}: $e');
      }
    }

    serversToTest.sort(
          (a, b) => a.latency.compareTo(b.latency),
    );

    print('Working servers: ${serversToTest.length}');

    for (final server in serversToTest.take(5)) {
      print(
        'Server: ${server.url} | latency: ${server.latency} ms',
      );
    }

    return serversToTest;
  }

  /// Creates [Uri] from [Server] and [String] file
  Uri createTestUrl(Server server, String file) {
    return Uri.parse(
      Uri.parse(server.url).toString().replaceAll('upload.php', file),
    );
  }

  /// Returns urls for download test.
  List<String> generateDownloadUrls(
    Server server,
    int retryCount,
    List<FileSize> downloadSizes,
  ) {
    final downloadUriBase = createTestUrl(server, 'random{0}x{0}.jpg?r={1}');
    final result = <String>[];
    for (final ds in downloadSizes) {
      for (var i = 0; i < retryCount; i++) {
        result.add(
          downloadUriBase
              .toString()
              .replaceAll('%7B0%7D', FILE_SIZE_MAPPING[ds].toString())
              .replaceAll('%7B1%7D', i.toString()),
        );
      }
    }
    return result;
  }

  /// Returns [double] downloaded speed in MB/s.
  Future<double> testDownloadSpeed({
    required List<Server> servers,
    int simultaneousDownloads = 2,
    int retryCount = 3,
    List<FileSize> downloadSizes = defaultDownloadSizes,
  }) async {
    double downloadSpeed = 0;

    // Iterates over all servers, if one request fails, the next one is tried.
    for (final s in servers) {
      final testData = generateDownloadUrls(s, retryCount, downloadSizes);
      final semaphore = Semaphore(simultaneousDownloads);
      final tasks = <int>[];
      final stopwatch = Stopwatch()..start();

      try {
        await Future.forEach(testData, (String td) async {
          await semaphore.acquire();
          try {
            final data = await http.get(Uri.parse(td),
                headers: _headers);

            print(
              'Download ${Uri.parse(td).host}: '
                  '${data.statusCode} ${data.bodyBytes.length} bytes',
            );

            if (data.statusCode != 200) {
              throw Exception(
                'Download failed: ${data.statusCode}',
              );
            }

            tasks.add(data.bodyBytes.length);
          } finally {
            semaphore.release();
          }
        });
        stopwatch.stop();
        final _totalSize = tasks.reduce((a, b) => a + b);
        downloadSpeed = (_totalSize * 8 / 1024) /
            (stopwatch.elapsedMilliseconds / 1000) /
            1000;
        break;
      } catch (_) {
        continue;
      }
    }
    return downloadSpeed;
  }

  /// Returns [double] upload speed in MB/s.
  Future<double> testUploadSpeed({
    required List<Server> servers,
    int simultaneousUploads = 2,
    int retryCount = 3,
  }) async {
    double uploadSpeed = 0;
    for (final s in servers) {
      final testData = generateUploadData(retryCount);
      final semaphore = Semaphore(simultaneousUploads);
      final stopwatch = Stopwatch()..start();
      final tasks = <int>[];

      try {
        await Future.forEach(testData, (String td) async {
          await semaphore.acquire();
          try {
            // do post request to measure time for upload
            final response = await http.post(
              Uri.parse(s.url),
              headers: _headers,
              body: td,
            );

            print(
              'Upload ${s.url}: '
                  '${response.statusCode}',
            );

            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw Exception(
                'Upload failed: ${response.statusCode}',
              );
            }

            tasks.add(td.length);
          } finally {
            semaphore.release();
          }
        });
        stopwatch.stop();
        final _totalSize = tasks.reduce((a, b) => a + b);
        uploadSpeed = (_totalSize * 8 / 1024) /
            (stopwatch.elapsedMilliseconds / 1000) /
            1000;
        break;
      } catch (_) {
        continue;
      }
    }
    return uploadSpeed;
  }

  /// Generate list of [String] urls for upload.
  List<String> generateUploadData(int retryCount) {
    final random = Random();
    final result = <String>[];

    for (var sizeCounter = 1; sizeCounter < maxUploadSize + 1; sizeCounter++) {
      final size = sizeCounter * 200 * 1024;
      final builder = StringBuffer()
        ..write('content ${sizeCounter.toString()}=');

      for (var i = 0; i < size; ++i) {
        builder.write(hars[random.nextInt(hars.length)]);
      }

      for (var i = 0; i < retryCount; i++) {
        result.add(builder.toString());
      }
    }

    return result;
  }
}
