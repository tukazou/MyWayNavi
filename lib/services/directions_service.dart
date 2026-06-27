import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../utils/polyline_decoder.dart';

class DirectionsResult {
  final List<LatLng> points;
  const DirectionsResult(this.points);
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
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    final originParam = '${origin.latitude},${origin.longitude}';
    final destinationParam = Uri.encodeComponent(destination);

    final url = 'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$originParam'
        '&destination=$destinationParam'
        '&mode=$mode'
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

    final encodedPolyline = routes[0]['overview_polyline']['points'];
    final decodedPoints = polylineToLatLng(decodePolyline(encodedPolyline));
    return DirectionsResult(decodedPoints);
  }
}
