import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../models/chat_message.dart';
import '../services/directions_service.dart';
import '../services/gemini_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final DirectionsService _directionsService = DirectionsService();
  final GeminiService _geminiService = GeminiService();

  GoogleMapController? _mapController;
  Position? _currentPosition;

  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  final TextEditingController _destinationController = TextEditingController();

  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isWaitingForReply = false;

  RouteOptions? _pendingRouteOptions;
  DirectionsResult? _pendingGuidanceRoute;

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
    _chatInputController.dispose();
    _chatScrollController.dispose();
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

  // ルート選択時：polylineの描画だけを行う（自動走行デモはまだ開始しない）
  void _drawRoute(DirectionsResult route) {
    final decodedPoints = route.points;

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
  }

  // 🏃‍♂️ 【自動走行デモシステム】「案内開始」ボタンが押されたときにのみ呼ばれる
  void _startDemo(List<LatLng> decodedPoints) {
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
  }

  String _buildRouteInfoPrompt(RouteOptions options) {
    final a = options.routeA;
    final buffer = StringBuffer()..writeln('[ルート情報]');
    buffer.writeln(
      'ルートA：高速優先／所要${a.durationMinutes}分／距離${a.distanceKm.toStringAsFixed(1)}km',
    );
    final b = options.routeB;
    if (b != null) {
      buffer.writeln(
        'ルートB：高速を使わないルート／所要${b.durationMinutes}分／距離${b.distanceKm.toStringAsFixed(1)}km',
      );
    } else {
      buffer.writeln('ルートB：高速を使わないルートは見つかりませんでした。ルートAのみで案内してください。');
    }
    return buffer.toString();
  }

  Future<void> _searchRoute() async {
    if (_currentPosition == null || _destinationController.text.isEmpty) return;

    setState(() {
      _isWaitingForReply = true;
      _pendingRouteOptions = null;
    });
    _scrollChatToBottom();

    RouteOptions options;
    try {
      options = await _directionsService.fetchRouteOptions(
        origin: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        destination: _destinationController.text,
      );
    } on DirectionsException catch (e) {
      if (mounted) {
        setState(() {
          _isWaitingForReply = false;
          _chatMessages.add(ChatMessage(ChatSender.assistant, e.message));
        });
      }
      _scrollChatToBottom();
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isWaitingForReply = false;
          _chatMessages.add(
            const ChatMessage(ChatSender.assistant, 'ルート検索中にエラーが発生しました'),
          );
        });
      }
      _scrollChatToBottom();
      return;
    }

    final prompt = _buildRouteInfoPrompt(options);

    try {
      final reply = await _geminiService.sendMessage(prompt);
      if (!mounted) return;
      setState(() {
        _chatMessages.add(ChatMessage(ChatSender.assistant, reply));
        _pendingRouteOptions = options;
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(ChatMessage(ChatSender.assistant, e.message));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          const ChatMessage(ChatSender.assistant, 'エラーが発生しました。もう一度お試しください'),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWaitingForReply = false;
        });
      }
      _scrollChatToBottom();
    }
  }

  void _selectRoute(DirectionsResult route, String routeLabel) {
    if (_pendingRouteOptions == null) return;
    setState(() {
      _pendingRouteOptions = null;
      _pendingGuidanceRoute = route;
    });
    _drawRoute(route);

    setState(() {
      _chatMessages.add(
        ChatMessage(
          ChatSender.assistant,
          '承知しました。では$routeLabelでご案内します。準備ができたら「案内開始」を押してください。',
        ),
      );
    });
    _scrollChatToBottom();
  }

  void _startGuidance() {
    final route = _pendingGuidanceRoute;
    if (route == null) return;
    setState(() {
      _pendingGuidanceRoute = null;
    });
    _startDemo(route.points);
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _isWaitingForReply) return;

    setState(() {
      _chatMessages.add(ChatMessage(ChatSender.user, text));
      _isWaitingForReply = true;
    });
    _chatInputController.clear();
    _scrollChatToBottom();

    try {
      final reply = await _geminiService.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _chatMessages.add(ChatMessage(ChatSender.assistant, reply));
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(ChatMessage(ChatSender.assistant, e.message));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          const ChatMessage(ChatSender.assistant, 'エラーが発生しました。もう一度お試しください'),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWaitingForReply = false;
        });
      }
      _scrollChatToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyWayNavi ルート検索'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 55,
            child: Stack(
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
          ),
          Expanded(
            flex: 45,
            child: _buildChatPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _chatMessages.length + (_isWaitingForReply ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _chatMessages.length) {
                  return _buildChatBubble(
                    ChatSender.assistant,
                    '考え中…',
                    isLoading: true,
                  );
                }
                final message = _chatMessages[index];
                return _buildChatBubble(message.sender, message.text);
              },
            ),
          ),
          if (_pendingRouteOptions != null) _buildRouteChoiceButtons(),
          if (_pendingGuidanceRoute != null) _buildStartGuidanceButton(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatInputController,
                      decoration: const InputDecoration(
                        hintText: 'MyWayNaviに話しかける',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: _isWaitingForReply ? null : _sendChatMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteChoiceButtons() {
    final options = _pendingRouteOptions!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _selectRoute(options.routeA, 'ルートA'),
              child: const Text('ルートAで行く'),
            ),
          ),
          if (options.routeB != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _selectRoute(options.routeB!, 'ルートB'),
                child: const Text('ルートBで行く'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartGuidanceButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _startGuidance,
          icon: const Icon(Icons.navigation),
          label: const Text('案内開始'),
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatSender sender, String text, {bool isLoading = false}) {
    final isUser = sender == ChatSender.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[100] : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(text),
                ],
              )
            : Text(text),
      ),
    );
  }
}
