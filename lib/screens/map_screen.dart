import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/directions_service.dart';
import '../services/gemini_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final DirectionsService _directionsService = DirectionsService();
  final GeminiService _geminiService = GeminiService(); // 🧪 Gemini疎通確認用

  GoogleMapController? _mapController;
  Position? _currentPosition;

  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  final TextEditingController _destinationController = TextEditingController();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _demoTimer;

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
    _demoTimer?.cancel();
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
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    });
  }

  void _searchRoute() async {
    if (_currentPosition == null || _destinationController.text.isEmpty) return;

    try {
      final result = await _directionsService.fetchRoute(
        origin: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        destination: _destinationController.text,
      );
      final decodedPoints = result.points;

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

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(decodedPoints.first, 15.0),
      );

      // 🏃‍♂️ 【自動走行デモシステム】
      _demoTimer?.cancel();
      int pointIndex = 0;

      _demoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
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
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          );
        });

        _mapController?.animateCamera(CameraUpdate.newLatLng(nextPoint));
        pointIndex++;
      });
    } on DirectionsException catch (e) {
      _showRouteError(e.message);
    } catch (e) {
      _showRouteError('ルート検索中にエラーが発生しました');
    }
  }

  void _showRouteError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // 🧪 Gemini API疎通確認用（疎通確認後は削除してよい）
  Future<void> _testGeminiConnection() async {
    const fixedPrompt = 'こんにちは。あなたは何ができますか?';
    String resultText;
    try {
      resultText = await _geminiService.sendMessage(fixedPrompt);
    } on GeminiException catch (e) {
      resultText = e.message;
    } catch (e) {
      resultText = 'Gemini疎通確認中にエラーが発生しました';
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gemini疎通確認結果'),
        content: SingleChildScrollView(child: Text(resultText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
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
            markers: _markers,
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
      // 🧪 Gemini API疎通確認用ボタン（疎通確認後は削除してよい）
      floatingActionButton: FloatingActionButton(
        heroTag: 'gemini_debug_button',
        backgroundColor: Colors.deepPurple,
        onPressed: _testGeminiConnection,
        child: const Icon(Icons.smart_toy),
      ),
    );
  }
}
