import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // 👈 TimerやStreamSubscriptionに必要

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {}; // 👈 【コレを追加】ピンを管理するセット
  final TextEditingController _destinationController = TextEditingController();

  StreamSubscription<Position>? _positionStreamSubscription; 
  Timer? _demoTimer; // 👈 全角スペースを削除し、正しく修正

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(35.681228, 139.767059),
    zoom: 15.0,
  );

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _demoTimer?.cancel(); // 👈 タイマーの破棄を追加
    super.dispose();
  }

  void _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    });
  }

  void _searchRoute() async {
    if (_currentPosition == null || _destinationController.text.isEmpty) return;

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    final origin = '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = Uri.encodeComponent(_destinationController.text);

    final url = 'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin'
        '&destination=$destination'
        '&mode=walking'
        '&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'].isNotEmpty) {
          final points = data['routes'][0]['overview_polyline']['points'];
          final decodedPoints = _convertToLatLng(_decodePoly(points));

          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: decodedPoints,
                color: Colors.blue,
                width: 6,
              ),
            );
          });

          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(decodedPoints.first, 15.0),
          );

          // 🏃‍♂️ 【自動走行デモシステム】
          _demoTimer?.cancel();
          int pointIndex = 0;

          _demoTimer = Timer.periodic(const Duration(seconds: 1), (timer) { // 👈 正しく修正
            if (pointIndex >= decodedPoints.length) {
              timer.cancel();
              return;
            }

            final nextPoint = decodedPoints[pointIndex];
            setState(() {
              // 🏃‍♂️ 現在地オブジェクトを正しく更新（...ではなく、すべてのパラメータを記述）
              _currentPosition = Position(
                latitude: nextPoint.latitude,
                longitude: nextPoint.longitude,
                timestamp: DateTime.now(),
                accuracy: 1.0,
                altitude: 0.0,
                heading: 0.0,
                speed: 0.0,
                speedAccuracy: 0.0,
                altitudeAccuracy: 0.0,
                headingAccuracy: 0.0,
              );

              // 📍 現在地に赤いピンを立てる
              _markers.clear();
              _markers.add(
                Marker(
                  markerId: const MarkerId('current_pin'),
                  position: nextPoint,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), // 赤いピン
                ),
              );
            });
            
            _mapController!.animateCamera(CameraUpdate.newLatLng(nextPoint));
            pointIndex++;
          });

        }
      }
    } catch (e) {
      print('Route search error: $e');
    }
  }

  List<PointLatLng> _decodePoly(String encoded) {
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

  List<LatLng> _convertToLatLng(List<PointLatLng> points) {
    return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyWayNavi ルート検索'),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              _determinePosition();
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            polylines: _polylines,
            markers: _markers, // 👈 【ココを追加！】
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destinationController,
                        decoration: const InputDecoration(
                          hintText: '目的地を入力（例: 秋葉原駅）',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.blue),
                      onPressed: _searchRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PointLatLng {
  final double latitude;
  final double longitude;
  const PointLatLng(this.latitude, this.longitude);
}