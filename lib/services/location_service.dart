import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';

class PlaceResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;

  const PlaceResult({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });
}

class LocationService {
  static const _defaultRadiusM = 200.0;

  /// Searches Nominatim (OpenStreetMap) for places matching [query].
  /// Returns an empty list on any network / parse error.
  static Future<List<PlaceResult>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '5',
      'addressdetails': '0',
    });
    final client = HttpClient();
    try {
      final response = await client
          .getUrl(uri)
          .then((req) {
            req.headers.set('User-Agent', 'CadenceApp/1.0 (Android)');
            return req.close();
          })
          .timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return [];
      final data = jsonDecode(body) as List;
      return data.map((e) {
        final full = e['display_name'] as String;
        final short = full.split(',').first.trim();
        return PlaceResult(
          displayName: full,
          shortName: short.isEmpty ? full : short,
          lat: double.parse(e['lat'] as String),
          lng: double.parse(e['lon'] as String),
        );
      }).toList();
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  /// Requests location permission. Returns true when granted.
  static Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  static Future<Position> _getPosition() async {
    final granted = await requestPermission();
    if (!granted) {
      throw Exception(
          'Location permission denied. Enable it in Settings to check in.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Haversine distance in metres between two lat/lng points.
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  /// Checks whether the device is within [radiusMeters] of ([targetLat], [targetLng]).
  /// Throws a user-readable [Exception] on permission / timeout failures.
  static Future<({bool withinRange, double distance})> checkAtLocation(
    double targetLat,
    double targetLng, {
    double radiusMeters = _defaultRadiusM,
  }) async {
    final pos = await _getPosition();
    // Android reports when a fix came from a mock provider. Cheap to check and
    // it blocks the obvious spoof; a rooted device can still defeat it.
    if (pos.isMocked) {
      throw Exception(
          'Mock location detected. Turn off any location-spoofing app to check in.');
    }
    final dist =
        distanceMeters(pos.latitude, pos.longitude, targetLat, targetLng);
    return (withinRange: dist <= radiusMeters, distance: dist);
  }
}
