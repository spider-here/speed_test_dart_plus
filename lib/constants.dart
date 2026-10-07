import 'package:speed_test_dart/enums/file_size.dart';

const configUrl = 'https://www.speedtest.net/speedtest-config.php';

const serversUrls = [
  'https://www.speedtest.net/speedtest-servers-static.php',
  'https://c.speedtest.net/speedtest-servers-static.php',
  'https://www.speedtest.net/speedtest-servers.php',
  'https://c.speedtest.net/speedtest-servers.php'
];

/// Our own server list, used instead of speedtest.net's IP-based list.
/// Add more entries here to test servers from other countries.
/// 'url' must end with 'upload.php'.
const customServers = <Map<String, Object>>[
  {
    'id': 2251,
    'name': 'Islamabad',
    'country': 'Pakistan',
    'sponsor': 'PTCL BROADBAND',
    'host': 'speedtest.ptcl.net:8080',
    'url': 'http://speedtest.ptcl.net:8080/speedtest/upload.php',
    'lat': 33.7167,
    'lon': 73.0667,
  },
  {
    'id': 46859,
    'name': 'Islamabad',
    'country': 'Pakistan',
    'sponsor': 'Dream Internet Services',
    'host': 'speedtest.dreamnet.com.pk:8080',
    'url': 'http://speedtest.dreamnet.com.pk:8080/speedtest/upload.php',
    'lat': 33.7167,
    'lon': 73.0667,
  },
  {
    'id': 35433,
    'name': 'Islamabad',
    'country': 'Pakistan',
    'sponsor': 'KK Networks',
    'host': 'speedtest-isb.kknetworks.com.pk:8080',
    'url': 'http://speedtest-isb.kknetworks.com.pk:8080/speedtest/upload.php',
    'lat': 33.7167,
    'lon': 73.0667,
  },
  {
    'id': 55226,
    'name': 'Islamabad',
    'country': 'Pakistan',
    'sponsor': 'BELLACOM',
    'host': 'speedtest.bellacom.com.pk:8080',
    'url': 'http://speedtest.bellacom.com.pk:8080/speedtest/upload.php',
    'lat': 33.7167,
    'lon': 73.0667,
  },
  {
    'id': 72905,
    'name': 'Islamabad',
    'country': 'Pakistan',
    'sponsor': 'Gamma Links',
    'host': 'speed.gammalinks.pk:8080',
    'url': 'http://speed.gammalinks.pk:8080/speedtest/upload.php',
    'lat': 33.6996,
    'lon': 73.0362,
  },
  {
    'id': 68721,
    'name': 'Rawalpindi',
    'country': 'Pakistan',
    'sponsor': 'MulticityInternet Pvt Ltd',
    'host': 'speedtest1.multicityinternet.com:8080',
    'url': 'http://speedtest1.multicityinternet.com:8080/speedtest/upload.php',
    'lat': 33.5651,
    'lon': 73.0169,
  },
];

/// Countries picked at random when `getSettings(randomCountry: true)` is used.
const randomCountries = [
  'Germany',
  'Singapore',
  'United States',
  'United Kingdom',
  'France',
  'Netherlands',
  'Italy',
  'Spain',
  'Sweden',
  'Switzerland',
];

const defaultDownloadSizes = [
  FileSize.SIZE_350,
  FileSize.SIZE_750,
  FileSize.SIZE_1500,
  FileSize.SIZE_3000,
];
const hars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const maxUploadSize = 4; // 400 KB