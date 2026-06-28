import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../utils/polyline_decoder.dart';

class DirectionsResult {
  final List<LatLng> points;
  final int durationSeconds;
  final int distanceMeters;

  const DirectionsResult({
    required this.points,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  int get durationMinutes => (durationSeconds / 60).round();
  double get distanceKm => distanceMeters / 1000;
}

class RouteOptions {
  final DirectionsResult routeA;
  final DirectionsResult? routeB;

  const RouteOptions({required this.routeA, this.routeB});
}

class DirectionsException implements Exception {
  final String message;
  const DirectionsException(this.message);

  @override
  String toString() => message;
}

class DirectionsService {
  Future<DirectionsResult> fetchRoute({
    required LatLng origin,
    required String destination,
    String mode = 'driving',
    bool avoidHighways = false,
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    final originParam = '${origin.latitude},${origin.longitude}';
    final destinationParam = Uri.encodeComponent(destination);

    final url = 'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$originParam'
        '&destination=$destinationParam'
        '&mode=$mode'
        '${avoidHighways ? '&avoid=highways' : ''}'
        '&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw DirectionsException(
        'ルート検索に失敗しました（status: ${response.statusCode}）',
      );
    }

    final data = json.decode(response.body);
    final routes = data['routes'] as List;
    if (routes.isEmpty) {
      throw const DirectionsException('ルートが見つかりませんでした');
    }

    final route = routes[0];
    final encodedPolyline = route['overview_polyline']['points'];
    final decodedPoints = polylineToLatLng(decodePolyline(encodedPolyline));

    final leg = route['legs'][0];
    final durationSeconds = leg['duration']['value'] as int;
    final distanceMeters = leg['distance']['value'] as int;

    return DirectionsResult(
      points: decodedPoints,
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
    );
  }

  /// 高速優先（ルートA）と下道優先（ルートB）の2案を取得する。
  /// ルートBが取得できない場合（高速なしルートが存在しない等）はnullになる。
  Future<RouteOptions> fetchRouteOptions({
    required LatLng origin,
    required String destination,
  }) async {
    final routeA = await fetchRoute(origin: origin, destination: destination);

    DirectionsResult? routeB;
    try {
      routeB = await fetchRoute(
        origin: origin,
        destination: destination,
        avoidHighways: true,
      );
    } catch (e) {
      routeB = null;
    }

    return RouteOptions(routeA: routeA, routeB: routeB);
  }
}
