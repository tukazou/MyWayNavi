import 'package:google_maps_flutter/google_maps_flutter.dart';

class PointLatLng {
  final double latitude;
  final double longitude;
  const PointLatLng(this.latitude, this.longitude);
}

List<PointLatLng> decodePolyline(String encoded) {
  List<PointLatLng> poly = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    poly.add(PointLatLng(lat / 1E5, lng / 1E5));
  }
  return poly;
}

List<LatLng> polylineToLatLng(List<PointLatLng> points) {
  return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
}
