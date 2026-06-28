# Issue 5 実装指示書 ― 渋滞オーケストレーション

対象：MyWayNavi（Flutter + Cloud Run/FastAPI）
担当：Claude Code（直接ファイル編集）
前提資料：技術仕様書 v0.2 第4章
作成：2026-06-28

---

## 0. ゴール

自動走行デモ中、赤マーカーが三郷JCT手前のトリガー座標に到達したら擬似渋滞を発火し、
**ルート1（並ぶ）／ルート2（迂回）の2案＋Geminiの状況説明**を提示、ユーザーのタップ選択で
地図のルートを差し替えて走行を再開する。デモシナリオのステップ7〜9に対応する。

**この指示書のスコープ外**：通常のルート検索（Flutter直）、CI/CD、駐車場案内（Issue 6）、モデル復帰（Issue 1）。

---

## 1. 確定済みの設計判断（実装前に動かさないこと）

1. **fat backend**：高度なフロー（渋滞迂回）は Cloud Run の `/reroute` に集約する。通常ルート検索は Flutter 直のまま。
2. **検知は擬似化**：実渋滞APIは使わない。トリガー座標への到達で1回だけ発火（再現性優先）。
3. **ETAは TRAFFIC_UNAWARE ＋ 遅延注入**：
   - ルート1 ＝ Routes API 素値 ＋ `injected_delay_min`
   - ルート2 ＝ Routes API 素値（遅延なし）
4. **迂回は waypoint 強制**：三郷中央IC→三郷流山橋→流山IC再流入→柏IC→MOVIX。
5. **fallback あり**：`/reroute` 内で Routes API が **エラー、または期待した三郷中央経由になっていない**場合は、キャッシュ/ハードコードのポリラインで即応答（`source: "fallback"`）。

---

## 2. 定数・座標表（暫定値）

すべて WGS84（lat, lng）。Place ID は確認用。

| 用途 | 名称 | lat | lng | Place ID |
|---|---|---|---|---|
| トリガー座標 | 三郷JCT手前（外環道上） | 35.776511 | 139.888695 | ― |
| 迂回 via 点 | 三郷流山橋 | 35.8652896 | 139.898173 | ChIJI7IsKzaaGGARVLFgQ218DH0 |
| （参考）流山IC | 流山IC | 35.877887 | 139.899688 | ChIJHQcHE9KbGGARA96eMw1sAUc |
| （参考）三郷中央IC | 三郷中央IC | 35.8248732 | 139.8710397 | ChIJ60yI8ZOaGGARWo-kthHi-J4 |
| 目的地 | MOVIX柏の葉（ららぽーと柏の葉内） | 35.8933745 | 139.9518514 | ChIJg37P_xOcGGARe9o17fc77ug |

**渋滞イベント（固定値）**

```json
{
  "id": "misato_jct",
  "location_label": "三郷JCT合流部（三郷IC付近）",
  "length_km": 2.0,
  "injected_delay_min": 20,
  "note": "伸びる可能性あり"
}
```

> via点（三郷流山橋）は「一度三郷中央で降りないと辿り着けない位置」に置くための暫定値。
> 実レスポンスで三郷中央経由にならない／旧・流山橋を引く場合は、流山IC側（35.878付近）へ少し寄せて再調整する。

---

## 3. バックエンド（Cloud Run / FastAPI）

> まず既存の FastAPI アプリ（`/chat`・`/health` がある main）と Gemini 呼び出しモジュールの実ファイル名・関数を確認し、それに合わせて実装すること。以下はインターフェース仕様。

### 3.1 新規エンドポイント `POST /reroute`

**リクエスト**
```json
{
  "current_location": { "lat": 35.776511, "lng": 139.888695 },
  "destination": "MOVIX柏の葉",
  "congestion_event": { "id":"misato_jct","location_label":"三郷JCT合流部（三郷IC付近）","length_km":2.0,"injected_delay_min":20,"note":"伸びる可能性あり" },
  "conversation_history": []
}
```

**処理フロー**
1. `route1`（直進）を Routes API で検索 → 素値 `t1`（分）。
2. `route2`（迂回）を Routes API で検索（via点強制）→ 素値 `t2`（分）。
3. 期待形チェック（3.4）。NG なら fallback（3.5）。
4. ETA 組み立て：
   - `route_stay.eta_min = t1 + injected_delay_min`
   - `route_detour.eta_min = t2`
5. `[渋滞情報]` を組み立て、既存 Gemini サービスで `reply` を生成（3.3）。
6. レスポンス（3.6）を返す。

### 3.2 Routes API 呼び出し（computeRoutes）

エンドポイント：`POST https://routes.googleapis.com/directions/v2:computeRoutes`
ヘッダ：`X-Goog-Api-Key: <KEY>`、`Content-Type: application/json`、
`X-Goog-FieldMask: routes.duration,routes.staticDuration,routes.distanceMeters,routes.polyline.encodedPolyline`

APIキーは既存の env 管理（`flutter_dotenv` ではなく **バックエンド側の環境変数**）から読む。クライアントには出さない。

**route1（直進）ボディ**
```json
{
  "origin": { "location": { "latLng": { "latitude": 35.776511, "longitude": 139.888695 } } },
  "destination": { "location": { "latLng": { "latitude": 35.8933745, "longitude": 139.9518514 } } },
  "travelMode": "DRIVE",
  "routingPreference": "TRAFFIC_UNAWARE",
  "polylineEncoding": "ENCODED_POLYLINE"
}
```

**route2（迂回）ボディ**：route1 に intermediates を追加
```json
{
  "origin": { "location": { "latLng": { "latitude": 35.776511, "longitude": 139.888695 } } },
  "intermediates": [
    { "location": { "latLng": { "latitude": 35.8652896, "longitude": 139.898173 } }, "via": true }
  ],
  "destination": { "location": { "latLng": { "latitude": 35.8933745, "longitude": 139.9518514 } } },
  "travelMode": "DRIVE",
  "routingPreference": "TRAFFIC_UNAWARE",
  "polylineEncoding": "ENCODED_POLYLINE"
}
```

- `via: true` でその点を「経由するが停車地点にしない」。これで三郷中央IC流出→橋→流山IC再流入の形を誘導する。
- 素値は `staticDuration`（`TRAFFIC_UNAWARE` では `duration == staticDuration`）を秒で受け取り、分へ切り上げ。
- `routes[0].polyline.encodedPolyline` をそのままレスポンスへ載せる。

### 3.3 Gemini 呼び出し（`[渋滞情報]`）

既存の Gemini サービス（`/chat` で使っているもの）を再利用。システムプロンプトに既存ルール
「数値は自分で作らず渡された値を使う／押しつけない／簡潔に」を踏襲し、以下を user 側メッセージとして渡す。
**数値（2km・20分・+10分）は埋め込んだ実値を渡し、Geminiには生成させない。**

```
[渋滞情報]
- 渋滞地点：三郷JCT合流部（三郷IC付近）
- 渋滞の長さ：約2km
- 通過予測：約20分、さらに伸びる可能性あり
- ルート1（並ぶ）：このまま常磐道。早いが三郷JCTの渋滞に停まる。到着 {route_stay_eta}分後
- ルート2（迂回）：三郷中央ICで降りて三郷流山橋経由、流山ICで再流入。到着 {route_detour_eta}分後（約+{diff}分）だが停まらずスムーズ

上記を運転者に簡潔に説明し、「並ぶ／迂回」のどちらにするか尋ねてください。判断は委ねること。
```

`{diff} = route_detour.eta_min - (route_stay.eta_min - injected_delay_min)` 等、表示が自然になるよう算出（マイナスになる場合は「ほぼ同じ」と表現できるよう数値だけ渡してGemini任せでよい）。

### 3.4 期待形チェック（fallback 判定）

以下のいずれかで **fallback** へ：
1. Routes API が非200／タイムアウト／例外／`routes` 空。
2. route2 が迂回になっていない疑い（簡易判定）：`t2` が `t1` とほぼ同じ（例：差が +3分未満）＝ via が効かず直進と同形の可能性。
3. （任意）`t2` が異常に長い（例：`t1 + 40分` 超）＝ 旧流山橋など遠回りを引いた可能性。

> 2 はしきい値で誤検知し得るので、まずは「1（エラー）＋ 2（差が小さすぎ）」だけ実装。3 は様子見でコメントアウト可。

### 3.5 fallback（ハードコード）

- 一度 `/reroute` を正常応答させ、その時の `route_stay` / `route_detour` の **encodedPolyline を定数として保存**（`FALLBACK_STAY_POLYLINE` / `FALLBACK_DETOUR_POLYLINE`）。
- fallback 時はこの2本＋固定ETA（例：`route_stay.eta_min=55`, `route_detour.eta_min=45`）を返し、`reply` も固定文面（3.3のテンプレを文章化したもの）を返す。Geminiも落ちている可能性を考え、fallback時はGeminiを呼ばず固定replyにする。
- `source: "fallback"` を必ず付与。

### 3.6 レスポンス

```json
{
  "reply": "この先、三郷JCTの合流で約2km・20分ほどの渋滞があり…どうしますか？",
  "action": "show_reroute",
  "routes": [
    { "id":"route_stay","label":"並ぶ（このまま常磐道）","polyline":"<encoded>","eta_min":55,"eta_breakdown":{"api_static_min":35,"injected_delay_min":20} },
    { "id":"route_detour","label":"迂回（三郷中央IC→三郷流山橋→流山IC）","polyline":"<encoded>","eta_min":45,"eta_breakdown":{"api_static_min":45,"injected_delay_min":0} }
  ],
  "source": "live"
}
```

---

## 4. Flutter クライアント

> 自動走行デモのマーカー移動ロジック（おそらく `Timer` でポリライン上の点を順送りしている箇所）を特定し、そこにトリガー判定を足す。既存のルート選択UI・チャットバブル・ポリライン描画を再利用すること。

### 4.1 トリガー検知

追加 state：
```dart
bool _congestionFired = false;   // 1回だけ発火
bool _congestionActive = false;  // 選択待ち中（移動停止）
```

マーカー位置更新のたびに（発火前のみ）距離判定：
```dart
const triggerLat = 35.776511, triggerLng = 139.888695;
const triggerRadiusM = 150.0;
if (!_congestionFired) {
  final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, triggerLat, triggerLng);
  if (d <= triggerRadiusM) {
    _congestionFired = true;
    _onCongestionDetected(pos); // 下記
  }
}
```
（`Geolocator.distanceBetween` 等、既存利用の距離関数に合わせる。なければ簡易Haversineで可。）

### 4.2 発火ハンドラ

```dart
Future<void> _onCongestionDetected(LatLng pos) async {
  _pauseAutoDrive();            // マーカー移動を止める
  setState(() => _congestionActive = true);
  _appendLoadingBubble();       // 既存のローディング表示
  final res = await rerouteService.reroute(
    currentLocation: pos,
    destination: 'MOVIX柏の葉',  // または目的地のlatLng
    congestionEvent: kDemoCongestionEvent, // 2章の固定値を定数化
  );
  _appendAiBubble(res.reply);   // 既存のAIバブル
  _drawRerouteRoutes(res.routes); // route_stay/route_detour を色分け描画
  _showStayDetourButtons(res.routes); // 既存ルート選択ボタンを流用
}
```

### 4.3 `/reroute` 呼び出しサービス

`useBackend` の既存バックエンドURLを使い、`POST {BACKEND_URL}/reroute` を実装（既存の `/chat` 呼び出しを踏襲）。
レスポンスを `RerouteResult { reply, action, routes:[RouteOption], source }` にパース。`RouteOption { id,label,polyline,etaMin }`。
`polyline` は encodedPolyline。描画時に `flutter_polyline_points` 等でデコードして `List<LatLng>` 化（既存のデコード手段に合わせる）。

### 4.4 選択ハンドリングと走行再開

```dart
void _onSelectStay() {
  _clearRerouteExtraPolyline();      // 迂回ポリラインを消す
  setState(() => _congestionActive = false);
  _resumeAutoDrive();                // 元ルートの続きから再開
}

void _onSelectDetour(RouteOption detour) {
  final pts = decodePolyline(detour.polyline);
  _replaceDrivePathFrom(currentPos: _marker, newPath: pts); // 現在地以降の走行経路を迂回に差し替え
  setState(() => _congestionActive = false);
  _resumeAutoDrive();                // 迂回ポリライン上を走り続ける
}
```

- 「並ぶ」：元の残りポリラインをそのまま続行。
- 「迂回」：迂回 encodedPolyline をデコードして、現在地から先の走行経路に差し替えて続行。
- どちらも `_congestionActive=false` に戻し、`_congestionFired` は true のまま（再発火しない）。

---

## 5. 受け入れ基準（このデモが通る条件）

- [ ] 自動走行でマーカーがトリガー座標を通過した瞬間、**1回だけ**渋滞が発火する（2回目以降は発火しない）。
- [ ] チャットに Gemini の状況説明が出る：三郷JCTの渋滞・約2km・約20分・「並ぶ/迂回」を尋ね、判断は委ねるトーン。数値が固定値どおり。
- [ ] 地図に2本のポリラインが色分け表示される。route_stay は常磐道直進、route_detour は三郷中央IC流出→三郷流山橋→流山IC再流入の形。
- [ ] 「迂回」タップで走行経路が迂回に差し替わり、マーカーが MOVIX柏の葉まで走り続ける。「並ぶ」タップで元ルート続行。
- [ ] バックエンドログで `source` を確認（正常時 `live`、API障害時 `fallback` でもデモが破綻しない）。
- [ ] route_stay.eta_min ＝ API素値＋20、route_detour.eta_min ＝ API素値、になっている。

---

## 6. 段階コミット計画（小さく刻む）

1. backend：`/reroute` 雛形 ＋ Routes API route1/route2 ＋ ETA 組み立て、`reply` は仮文字列で JSON 返却。
2. backend：Gemini で `reply` 生成を接続。
3. backend：期待形チェック ＋ ハードコード fallback。
4. Flutter：トリガー検知（発火時はログ出力のみで挙動確認）。
5. Flutter：`/reroute` 呼び出し ＋ 2ルート描画 ＋ 並ぶ/迂回ボタン表示。
6. Flutter：選択ハンドリングと走行再開。
7. 調整：via座標・トリガー半径・固定値（20分等）をデモ映え優先でチューニング。

---

## 7. 注意・調整ポイント

- **via座標は要実機確認**：三郷中央経由にならない／旧流山橋を引く場合、via点を流山IC側（35.878付近）へ寄せる。最悪 via を2点（橋＋流山IC手前）にする手もあるが、まず1点で試す。
- **fallbackポリラインは「正常応答を1回取ってから」**コピーする。先にハードコードしようとしない。
- **APIキーはバックエンド環境変数**。クライアント `.env` に増やさない（過去のキー流出を踏まえ server 集約を維持）。
- **通常ルート検索は触らない**。今回の変更は高度系（`/reroute`）のみ。
- **Routes API 課金**：`TRAFFIC_UNAWARE` は低レイテンシ・低コスト側。クレジット残（8/18まで$300相当）内で問題なし。
- ドキュメント整合（Issue 8）：実装が固まったら技術仕様書 v0.2 の `/reroute` JSON を実体に合わせて更新する。
