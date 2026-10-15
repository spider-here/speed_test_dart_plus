library speed_test_dart;

import 'dart:async';
import 'dart:convert';
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
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    'Accept': 'application/xml,text/xml,*/*',
  };

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  };

  /// Country whose servers were used by the last [getSettings] call, or null
  /// if the fallback [customServers] list was used.
  String? lastCountry;

  /// Fetches servers of [country] (e.g. 'Germany') from speedtest.net's
  /// search API. Returns an empty list if the request is rejected.
  Future<List<Server>> _fetchServersByCountry(String country) async {
    final uri = Uri.parse(
      'https://www.speedtest.net/api/js/servers'
      '?engine=js&search=${Uri.encodeQueryComponent(country)}&limit=10',
    );
    final resp = await http.get(uri, headers: {
      ..._headers,
      'Accept': 'application/json',
    });
    if (resp.statusCode != 200) return <Server>[];

    final list = jsonDecode(resp.body) as List;
    return list.map((j) {
      final lat = double.parse(j['lat'].toString());
      final lon = double.parse(j['lon'].toString());
      return Server(
        int.parse(j['id'].toString()),
        j['name'].toString(),
        j['country'].toString(),
        j['sponsor'].toString(),
        j['host'].toString(),
        j['url'].toString(),
        lat,
        lon,
        99999999999,
        99999999999,
        Coordinate(lat, lon),
      );
    }).toList();
  }

  /// Tries [country], or, with [randomCountry], the countries in
  /// [randomCountries] in random order, until one returns servers.
  Future<List<Server>> _serversForCountry(
    String? country,
    bool randomCountry,
  ) async {
    final candidates = <String>[];
    if (country != null && country.trim().isNotEmpty) {
      candidates.add(country.trim());
    } else if (randomCountry) {
      candidates.addAll(List<String>.from(randomCountries)..shuffle());
    }

    for (final c in candidates) {
      try {
        final found = await _fetchServersByCountry(c);
        if (found.isNotEmpty) {
          lastCountry = c;
          return found;
        }
      } catch (_) {
        // try the next country
      }
    }
    lastCountry = null;
    return <Server>[];
  }

  /// By default a random country from [randomCountries] is used. Pass
  /// [country] to force a specific one, or set [randomCountry] to false to
  /// skip the country search. If nothing works (or the API is blocked),
  /// [customServers] is used.
  Future<Settings> getSettings({
    String? country,
    bool randomCountry = true,
  }) async {
    final response = await http.get(Uri.parse(configUrl), headers: _xmlHeaders);
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

    var servers = await _serversForCountry(country, randomCountry);
    print('Speedtest country used: ${lastCountry ?? 'custom list'}');

    // Fallback: our own list (constants.dart).
    if (servers.isEmpty) {
      servers = customServers.map((m) {
        final lat = (m['lat']! as num).toDouble();
        final lon = (m['lon']! as num).toDouble();
        return Server(
          m['id']! as int,
          m['name']! as String,
          m['country']! as String,
          m['sponsor']! as String,
          m['host']! as String,
          m['url']! as String,
          lat,
          lon,
          99999999999,
          99999999999,
          Coordinate(lat, lon),
        );
      }).toList();
    }

    final serversConfig = ServersList(servers);
    serversConfig.calculateDistances(settings.client.geoCoordinate);
    settings.servers = serversConfig.servers.toList();
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
      final stopwatch = Stopwatch();

      stopwatch.start();
      try {
        await http.get(latencyUri, headers: _headers).timeout(
              Duration(
                seconds: timeoutInSeconds,
              ),
              onTimeout: (() => http.Response(
                    '999999999',
                    500,
                  )),
            );
        // If a server fails the request, continue in the iteration
      } catch (_) {
        continue;
      } finally {
        stopwatch.stop();
      }

      final latency = stopwatch.elapsedMilliseconds / retryCount;
      if (latency < 500) {
        server.latency = latency;
        serversToTest.add(server);
      }
    }

    serversToTest.sort((a, b) => a.latency.compareTo(b.latency));
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

  /// Returns download speed in Mb/s.
  ///
  /// [onProgress] is called with the running speed in Mb/s while bytes are
  /// still arriving (about 10 times a second). The last call equals the
  /// returned value, so a speedometer can follow it until the test ends.
  Future<double> testDownloadSpeed({
    required List<Server> servers,
    int simultaneousDownloads = 2,
    int retryCount = 3,
    List<FileSize> downloadSizes = defaultDownloadSizes,
    void Function(double mbps)? onProgress,
  }) async {
    // Iterates over all servers, if one request fails, the next one is tried.
    for (final s in servers) {
      final testData = generateDownloadUrls(s, retryCount, downloadSizes);
      final semaphore = Semaphore(simultaneousDownloads);
      final tasks = <int>[];
      final stopwatch = Stopwatch()..start();
      final client = http.Client();
      var totalBytes = 0;
      var lastReportMs = -_progressIntervalMs;

      void report() {
        final callback = onProgress;
        if (callback == null) return;
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed < _progressWarmupMs) return;
        if (elapsed - lastReportMs < _progressIntervalMs) return;
        lastReportMs = elapsed;
        callback(_megabitsPerSecond(totalBytes, elapsed));
      }

      try {
        await Future.forEach(testData, (String td) async {
          await semaphore.acquire();
          try {
            final request = http.Request('GET', Uri.parse(td));
            request.headers.addAll(_headers);
            final response = await client.send(request);
            var received = 0;
            await for (final chunk in response.stream) {
              received += chunk.length;
              totalBytes += chunk.length;
              report();
            }
            print(
              'Download ${Uri.parse(td).host}: '
              '${response.statusCode} $received bytes',
            );
            tasks.add(received);
          } finally {
            semaphore.release();
          }
        });
        stopwatch.stop();
        final totalSize = tasks.reduce((a, b) => a + b);
        final downloadSpeed = _megabitsPerSecond(
          totalSize,
          stopwatch.elapsedMilliseconds,
        );
        onProgress?.call(downloadSpeed);
        return downloadSpeed;
      } on Object {
        continue;
      } finally {
        client.close();
      }
    }
    return 0;
  }

  /// Returns upload speed in Mb/s.
  ///
  /// [onProgress] is called with the running speed in Mb/s while bytes are
  /// still being sent (about 10 times a second). The last call equals the
  /// returned value, so a speedometer can follow it until the test ends.
  Future<double> testUploadSpeed({
    required List<Server> servers,
    int simultaneousUploads = 2,
    int retryCount = 3,
    void Function(double mbps)? onProgress,
  }) async {
    for (final s in servers) {
      final testData = generateUploadData(retryCount);
      final semaphore = Semaphore(simultaneousUploads);
      final stopwatch = Stopwatch()..start();
      final tasks = <int>[];
      final client = http.Client();
      var totalBytes = 0;
      var lastReportMs = -_progressIntervalMs;

      void report() {
        final callback = onProgress;
        if (callback == null) return;
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed < _progressWarmupMs) return;
        if (elapsed - lastReportMs < _progressIntervalMs) return;
        lastReportMs = elapsed;
        callback(_megabitsPerSecond(totalBytes, elapsed));
      }

      try {
        await Future.forEach(testData, (String td) async {
          await semaphore.acquire();
          try {
            final bytes = utf8.encode(td);
            final request = _UploadRequest(
              Uri.parse(s.url),
              bytes,
              (sent) {
                totalBytes += sent;
                report();
              },
            );
            request.headers.addAll(_headers);
            request.headers['content-type'] = 'text/plain; charset=utf-8';
            final response = await client.send(request);
            print(
              'Upload ${s.url}: '
              '${response.statusCode}',
            );
            await response.stream.drain<void>();
            tasks.add(bytes.length);
          } finally {
            semaphore.release();
          }
        });
        stopwatch.stop();
        final totalSize = tasks.reduce((a, b) => a + b);
        final uploadSpeed = _megabitsPerSecond(
          totalSize,
          stopwatch.elapsedMilliseconds,
        );
        onProgress?.call(uploadSpeed);
        return uploadSpeed;
      } on Object {
        continue;
      } finally {
        client.close();
      }
    }
    return 0;
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

const _progressIntervalMs = 100;
const _progressWarmupMs = 200;
const _uploadChunkSize = 16 * 1024;

double _megabitsPerSecond(int bytes, int elapsedMs) {
  if (bytes <= 0 || elapsedMs <= 0) return 0;
  return (bytes * 8 / 1024) / (elapsedMs / 1000) / 1000;
}

/// POST body that reports each chunk as the socket accepts it.
class _UploadRequest extends http.BaseRequest {
  _UploadRequest(Uri url, this._bytes, this._onChunk) : super('POST', url) {
    contentLength = _bytes.length;
  }

  final List<int> _bytes;
  final void Function(int chunkLength) _onChunk;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    for (var start = 0; start < _bytes.length; start += _uploadChunkSize) {
      final end = min(start + _uploadChunkSize, _bytes.length);
      yield _bytes.sublist(start, end);
      _onChunk(end - start);
    }
  }
}
