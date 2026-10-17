library speed_test_dart;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:speed_test_dart/classes/classes.dart';
import 'package:speed_test_dart/constants.dart';
import 'package:speed_test_dart/enums/file_size.dart';
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

  /// Country the current test was launched from, taken from the speedtest
  /// config. India and Israel are contacted only when this matches them.
  String? _homeCountry;
  String? _homeCountryCode;

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
    bool randomCountry, {
    String? homeCountry,
  }) async {
    final candidates = <String>[];
    if (country != null && country.trim().isNotEmpty) {
      candidates.add(country.trim());
    } else {
      if (homeCountry != null && homeCountry.trim().isNotEmpty) {
        candidates.add(homeCountry.trim());
      }
      if (randomCountry) {
        final rest = List<String>.from(randomCountries)..shuffle();
        for (final name in rest) {
          if (!candidates.contains(name)) candidates.add(name);
        }
      }
    }

    for (final c in candidates) {
      if (!_mayContactCountry(c)) continue;
      try {
        final found = await _fetchServersByCountry(c);
        final allowed = found
            .where((server) => _mayContactCountry(server.country))
            .toList();
        if (allowed.isNotEmpty) {
          lastCountry = c;
          return allowed;
        }
      } catch (_) {
        // try the next country
      }
    }
    lastCountry = null;
    return <Server>[];
  }

  /// By default servers in the client's own country are used, because a
  /// far server measures the international path rather than the line speed.
  /// Pass [country] to force one, or set [randomCountry] to false to skip
  /// the random fallback. If nothing works, [customServers] is used.
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
    final settingsElement =
        XmlDocument.parse(response.body).getElement('settings');
    final settings = Settings.fromXMLElement(settingsElement);
    _homeCountryCode =
        settingsElement?.getElement('client')?.getAttribute('country');
    final homeCountry = _countryName(_homeCountryCode);
    _homeCountry = homeCountry;

    var servers = await _serversForCountry(
      country,
      randomCountry,
      homeCountry: country == null ? homeCountry : null,
    );
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

    servers = _withoutRestrictedServers(servers);

    final serversConfig = ServersList(servers);
    serversConfig.calculateDistances(settings.client.geoCoordinate);
    settings.servers = serversConfig.servers.toList();
    settings.servers.sort((a, b) => a.distance.compareTo(b.distance));

    return settings;
  }

  /// India and Israel are contacted only when the test launched there.
  bool _mayContactCountry(String? country) {
    final restricted = _restrictedCountry(country);
    if (restricted == null) return true;
    final homeName = _homeCountry?.trim().toLowerCase();
    final homeCode = _homeCountryCode?.trim().toLowerCase();
    if (restricted == 'india') {
      return homeName == 'india' || homeCode == 'in';
    }
    return homeName == 'israel' || homeCode == 'il';
  }

  List<Server> _withoutRestrictedServers(List<Server> servers) {
    return servers
        .where((server) => _mayContactCountry(server.country))
        .toList();
  }

  /// Returns a List[Server] with the best servers, ordered
  /// by lowest to highest latency.
  Future<List<Server>> getBestServers({
    required List<Server> servers,
    int retryCount = 2,
    int timeoutInSeconds = 2,
  }) async {
    final measured = await Future.wait(
      servers.map(
        (server) => _pingServer(server, retryCount, timeoutInSeconds),
      ),
    );
    final serversToTest = measured.whereType<Server>().toList()
      ..sort((a, b) => a.latency.compareTo(b.latency));
    for (final server in serversToTest.take(5)) {
      print(
        'Server: ${server.url} | latency: ${server.latency} ms',
      );
    }

    return serversToTest;
  }

  Future<Server?> _pingServer(
    Server server,
    int retryCount,
    int timeoutInSeconds,
  ) async {
    if (!_mayContactCountry(server.country)) return null;
    final stopwatch = Stopwatch()..start();
    try {
      await http
          .get(createTestUrl(server, 'latency.txt'), headers: _headers)
          .timeout(
            Duration(seconds: timeoutInSeconds),
            onTimeout: () => http.Response('999999999', 500),
          );
    } on Object {
      return null;
    } finally {
      stopwatch.stop();
    }

    final latency = stopwatch.elapsedMilliseconds / retryCount;
    if (latency >= 500) return null;
    server.latency = latency;
    return server;
  }

  /// Creates [Uri] from [Server] and [String] file
  Uri createTestUrl(Server server, String file) {
    return Uri.parse(server.url.replaceAll('upload.php', file));
  }

  /// Returns urls for download test.
  List<String> generateDownloadUrls(
    Server server,
    int retryCount,
    List<FileSize> downloadSizes,
  ) {
    final base = server.url.replaceAll(
      'upload.php',
      'random{0}x{0}.jpg?r={1}',
    );
    final result = <String>[];
    for (final ds in downloadSizes) {
      final size = FILE_SIZE_MAPPING[ds].toString();
      final withSize = base.replaceAll('{0}', size);
      for (var i = 0; i < retryCount; i++) {
        result.add(withSize.replaceAll('{1}', '$i'));
      }
    }
    return result;
  }

  /// Returns download speed in Mb/s.
  ///
  /// [simultaneousDownloads] files are fetched at once for [testDuration].
  /// The result ignores the first two seconds, so connection startup is not
  /// counted. [onProgress] receives that same running speed.
  Future<double> testDownloadSpeed({
    required List<Server> servers,
    int simultaneousDownloads = 6,
    int retryCount = 3,
    List<FileSize> downloadSizes = defaultDownloadSizes,
    Duration testDuration = const Duration(seconds: 20),
    void Function(double mbps)? onProgress,
  }) async {
    for (final server in servers) {
      if (!_mayContactCountry(server.country)) continue;
      final urls = generateDownloadUrls(
        server,
        retryCount,
        downloadSizes,
      ).reversed.toList();
      if (urls.isEmpty) continue;
      var cursor = 0;
      final speed = await _measure(
        connections: simultaneousDownloads,
        testDuration: testDuration,
        onProgress: onProgress,
        transfer: (client, meter, stopped) async {
          if (stopped()) return;
          final index = cursor;
          cursor++;
          final url = '${urls[index % urls.length]}&n=$index';
          final request = http.Request('GET', Uri.parse(url));
          request.headers.addAll(_headers);
          final response = await client.send(request);
          await for (final chunk in response.stream) {
            meter.add(chunk.length);
          }
        },
      );
      if (speed != null) return speed;
    }
    return 0;
  }

  /// Returns upload speed in Mb/s.
  ///
  /// [simultaneousUploads] uploads run at once for [testDuration]. The same
  /// body is sent again until the time is up. The result ignores the first
  /// two seconds. [onProgress] receives that same running speed.
  Future<double> testUploadSpeed({
    required List<Server> servers,
    int simultaneousUploads = 6,
    int retryCount = 3,
    Duration testDuration = const Duration(seconds: 20),
    void Function(double mbps)? onProgress,
  }) async {
    final body = _steadyUploadBody();
    for (final server in servers) {
      if (!_mayContactCountry(server.country)) continue;
      final speed = await _measure(
        connections: simultaneousUploads,
        testDuration: testDuration,
        onProgress: onProgress,
        transfer: (client, meter, stopped) async {
          if (stopped()) return;
          final request = _UploadRequest(
            Uri.parse(server.url),
            body,
            meter.add,
          );
          request.headers.addAll(_headers);
          request.headers['content-type'] = 'text/plain; charset=utf-8';
          final response = await client.send(request);
          await response.stream.drain<void>();
        },
      );
      if (speed != null) return speed;
    }
    return 0;
  }

  /// Generate list of upload bodies.
  List<String> generateUploadData(int retryCount) {
    final result = <String>[];
    for (var sizeCounter = 1; sizeCounter < maxUploadSize + 1; sizeCounter++) {
      final size = sizeCounter * 200 * 1024;
      final body = 'content $sizeCounter=${_filledText(size)}';
      for (var i = 0; i < retryCount; i++) {
        result.add(body);
      }
    }
    return result;
  }
}

const _progressIntervalMs = 100;
const _progressWarmupMs = 200;
const _steadyWarmupMs = 2000;
const _uploadChunkSize = 64 * 1024;
const _steadyUploadBodySize = 4 * 1024 * 1024;

const _countryNames = <String, String>{
  'PK': 'Pakistan',
  'DE': 'Germany',
  'SG': 'Singapore',
  'US': 'United States',
  'GB': 'United Kingdom',
  'FR': 'France',
  'NL': 'Netherlands',
  'IT': 'Italy',
  'ES': 'Spain',
  'SE': 'Sweden',
  'CH': 'Switzerland',
  'IN': 'India',
  'IL': 'Israel',
  'AE': 'United Arab Emirates',
  'SA': 'Saudi Arabia',
  'CA': 'Canada',
  'AU': 'Australia',
  'JP': 'Japan',
  'BR': 'Brazil',
};

double _megabitsPerSecond(int bytes, int elapsedMs) {
  if (bytes <= 0 || elapsedMs <= 0) return 0;
  return bytes * 8 / elapsedMs / 1000;
}

String? _countryName(String? code) {
  if (code == null || code.isEmpty) return null;
  return _countryNames[code.toUpperCase()];
}

/// India and Israel are used only when the test is launched from that country.
String? _restrictedCountry(String? country) {
  final name = country?.trim().toLowerCase();
  if (name == null || name.isEmpty) return null;
  if (name == 'in' || name == 'india') return 'india';
  if (name == 'il' || name == 'israel') return 'israel';
  return null;
}

Uint8List? _cachedUploadBody;

Uint8List _steadyUploadBody() {
  final cached = _cachedUploadBody;
  if (cached != null) return cached;
  final prefix = utf8.encode('content1=');
  final bytes = Uint8List(prefix.length + _steadyUploadBodySize);
  bytes.setRange(0, prefix.length, prefix);
  _fillLetters(bytes, prefix.length);
  _cachedUploadBody = bytes;
  return bytes;
}

String _filledText(int length) {
  return String.fromCharCodes(_letterBuffer(length));
}

Uint8List _letterBuffer(int length) {
  final bytes = Uint8List(length);
  _fillLetters(bytes, 0);
  return bytes;
}

void _fillLetters(Uint8List bytes, int start) {
  if (start >= bytes.length) return;
  const patternSize = 4096;
  final pattern = Uint8List(patternSize);
  final alphabet = hars.codeUnits;
  for (var i = 0; i < patternSize; i++) {
    pattern[i] = alphabet[i % alphabet.length];
  }
  var offset = start;
  while (offset < bytes.length) {
    final count = min(patternSize, bytes.length - offset);
    bytes.setRange(offset, offset + count, pattern);
    offset += count;
  }
}

Future<double?> _measure({
  required int connections,
  required Duration testDuration,
  required void Function(double mbps)? onProgress,
  required Future<void> Function(
    http.Client client,
    _Meter meter,
    bool Function() stopped,
  ) transfer,
}) async {
  final meter = _Meter(onProgress);
  final client = http.Client();
  var timedOut = false;
  var failed = false;
  final timer = Timer(testDuration, () {
    timedOut = true;
    client.close();
  });

  try {
    await Future.wait(
      List.generate(max(connections, 1), (_) async {
        while (!timedOut && !failed) {
          try {
            await transfer(client, meter, () => timedOut);
          } on Object {
            if (timedOut) return;
            failed = true;
            client.close();
            return;
          }
        }
      }),
    );
  } on Object {
    failed = true;
  } finally {
    timer.cancel();
    meter.stop();
    client.close();
  }

  if (failed || meter.totalBytes <= 0) return null;
  final speed = meter.mbps;
  onProgress?.call(speed);
  return speed;
}

class _Meter {
  _Meter(this.onProgress);

  final void Function(double mbps)? onProgress;
  final Stopwatch _watch = Stopwatch()..start();

  int totalBytes = 0;
  int _lastReportMs = -_progressIntervalMs;
  int? _markBytes;
  int _markMs = 0;

  void add(int bytes) {
    totalBytes += bytes;
    final elapsed = _watch.elapsedMilliseconds;
    if (_markBytes == null && elapsed >= _steadyWarmupMs) {
      _markBytes = totalBytes;
      _markMs = elapsed;
    }
    _report();
  }

  double get mbps {
    final elapsed = _watch.elapsedMilliseconds;
    final mark = _markBytes;
    if (mark != null && elapsed > _markMs) {
      return _megabitsPerSecond(totalBytes - mark, elapsed - _markMs);
    }
    return _megabitsPerSecond(totalBytes, elapsed);
  }

  void stop() => _watch.stop();

  void _report() {
    final callback = onProgress;
    if (callback == null) return;
    final elapsed = _watch.elapsedMilliseconds;
    if (elapsed < _progressWarmupMs) return;
    if (elapsed - _lastReportMs < _progressIntervalMs) return;
    _lastReportMs = elapsed;
    callback(mbps);
  }
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
    final bytes = _bytes;
    if (bytes is Uint8List) {
      for (var start = 0; start < bytes.length; start += _uploadChunkSize) {
        final end = min(start + _uploadChunkSize, bytes.length);
        yield Uint8List.sublistView(bytes, start, end);
        _onChunk(end - start);
      }
      return;
    }
    for (var start = 0; start < bytes.length; start += _uploadChunkSize) {
      final end = min(start + _uploadChunkSize, bytes.length);
      yield bytes.sublist(start, end);
      _onChunk(end - start);
    }
  }
}
