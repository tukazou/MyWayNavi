import asyncio
import os

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Routes API（computeRoutes）用。Directions API（Flutter直のルート検索）とは別エンドポイント。
# 同じMaps PlatformのAPIキーで動くが、GCPプロジェクト側で「Routes API」を
# 個別に有効化しておく必要がある。
GOOGLE_MAPS_API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
ROUTES_API_ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes"
ROUTES_FIELD_MASK = (
    "routes.duration,routes.staticDuration,routes.distanceMeters,"
    "routes.polyline.encodedPolyline"
)

# /reroute のデモ用固定値（Issue 5 技術仕様書 v0.2 第4章）
MISATO_JCT_TRIGGER = {"lat": 35.776511, "lng": 139.888695}
MISATO_NAGAREYAMA_BRIDGE_VIA = {"lat": 35.8652896, "lng": 139.898173}
MOVIX_KASHIWANOHA = {"lat": 35.8933745, "lng": 139.9518514}

# fallback用ポリライン（/rerouteのlive成功時のレスポンスから実値を採取済み）
FALLBACK_STAY_POLYLINE = r'arjyEa_ytYhXmS|`@aZrK{I|CwCdCiClA{AhA_BrFwI~@kBdB{Dj@uApDsKh@kBlCqL`D}OfAcG`@sBn@qDhAyE`A_C`AgBx@mAlAqAf@c@pBoAfBu@`Bc@jCc@zTuBLSxASrHu@~DO^@DBxLy@J^iF\KTyB^cUlBECGQkL~@{D`@iEn@{Cv@cBx@aBvAw@x@s@~@iAhBgAlC_ArDiBbJsDrRwAzGaDzLaA|CgDrIaAzBqA`CqBlDoAnB_CxCgAzA_@d@aMlLw\pVo`@zY}QdNeRfNuFtDsF`D}FrCuF|BsFjB}F|AaGnAeG~@iFl@mr@vFaGt@_KfBaOpCgHdAmNtAuYnCsJjAoF|@yFjAuElAqBl@_EzAuAf@mEvByDxByE|CgEdDyChCyAtAeFpFiGjH{DzEiC|CmB~BAVkFjHW^IXyAfBa@p@Uj@]dBSfDIn@Wr@_@h@a@Zc@Nc@Dg@Co@S_@W]e@Wq@S_Ac@aD[_AeHwLECgDoGmCyFe@kA?WgCuF_DoGmBcD_ByBeCqCgD_DgG_FwG}EcHqEeIwEgMiGwH_DmI{C_WgI{EgB{IoDiCcA}Ai@oEkA_Bg@mAk@oAs@kA{@oDgD}@u@oFsDaEaDaDwCgCkCyBiC_CcDuCuE{CyFKYiCaGqCiHaHkReFkMqEgKaDyGuCoF}DsGyCkEiBaC{GkI{EeFoCkCeXcV{EuEuHuHeJeKeK{LsNcRcFuGyDkEmJoJoNiMwEuEY?WSkBgBy@e@s@Qq@CiBHk@Eg@O][Sg@Gi@@i@Ly@Zy@~AiDv@yBf@}AFk@AOrAcGh@mCDeACgAScAa@aAg@o@k@c@w@Yo@G_@Da@RYZMj@@f@FVRVXLZ?^Oh@s@`AiBN[LGpFiOrA_EbIqT~AsDjBmDxBkDjBeCRW|A~@jB|@pA`@`ARL?bBh@~@P`Kx@nBDbCEtLoAQuD@oAVyC?[L_ALIfATHNARCL'
FALLBACK_DETOUR_POLYLINE = r'arjyEa_ytYhXmS|`@aZrK{I|CwCdCiClA{AhA_BrFwI~@kBdB{Dj@uApDsKh@kBlCqL`D}OfAcG`@sBn@qDhAyE`A_C`AgBx@mAlAqAf@c@pBoAfBu@`Bc@jCc@zTuBLSxASrHu@~DO^@DBxLy@J^iF\KTyB^cUlBECGQkL~@{D`@iEn@{Cv@cBx@aBvAw@x@s@~@iAhBgAlC_ArDiBbJsDrRwAzGaDzLaA|CgDrIaAzBqA`CqBlDoAnB_CxCgAzA_@d@aMlLw\pVo`@zY}QdNeRfNuFtDsF`D}FrCuF|BsFjB}F|AaGnAeG~@iFl@mr@vFaGt@_KfBaOpCgHdAmNtAuYnCsJjAoF|@yFjAuElAqBl@_EzAuAf@mEvByDxByE|CgEdDyChCyAtAeFpFiGjH{DzEiC|CmB~BAVkFjHW^IXyAfBa@p@Uj@]dBSfDIn@Wr@_@h@a@Zc@Nc@Dg@Co@S_@W]e@Wq@S_Ac@aD[_AeHwLECgDoGmCyFe@kA?WgCuF_DoGmBcD_ByBeCqCgD_DgG_FwG}EcHqEeIwEgMiGwH_DmI{C_WgI{EgB{IoDiCcA_@DyA_@wB[g@Eg@DsA^c@C_@Ww@u@u@a@GKu@[[]_@_AeBeCQSp@cBPk@?Sx@DvBRvBGV@hAMfAYx@e@j@i@b@e@h@W|Bg@OaC{@oIaBmPc@qAe@{EBwAmB{QsAaNqBwQk@oDw@aDmAqDgAiCoCcFy@iB]}@MQKWKUo@}AiBiFYu@Q]_BoEI[uAsCm@aA[]uAaA_@a@q@gA_EsHsAkCi@cASs@UeAKWI}@C{Ad@sS@mBPsHGoAUsA_@cAe@y@aAmAwDeEaBuBiBwCgAwBuAcDkA_Ee@oBiAkGw@}E]aAk@gAi@q@{@_A_AoA{A{C}FqJi@}@oAmCyFmOoKaZoA}DKIcAgCkDqJ_BkDwAgCwAqBiAoA{AiAaBy@{Ac@y@OmAMsAAaBHiOzAaBL]FSoE@oAVyC?[L_ALIfATHNARCL'
FALLBACK_STAY_ETA_MIN = 53
FALLBACK_DETOUR_ETA_MIN = 40

# 現在 gemini-3.5-flash がGoogle側の高負荷で503を返すことがあるため、
# 一時的に gemini-3.1-flash-lite をデフォルトにしている。
# 503が落ち着いたら GEMINI_MODEL=gemini-3.5-flash に戻すこと
# （環境変数で上書きできるので、コード変更なしで切り替え可能）。
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.1-flash-lite")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_ENDPOINT = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
)

MAX_RETRIES = 3
RETRYABLE_STATUS_CODES = {503, 429}

# Flutterからのアクセスを許可する。デモ用途のため当面はワイルドカード。
# 本番運用では実際のオリジンに絞ること。
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", "*").split(",")

SYSTEM_PROMPT = """\
あなたはMyWayNaviというAIドライビングパートナーです。
カーナビの「案内するだけ」の存在ではなく、ドライバーの好み・走行履歴・車種・目的地の性質を理解し、先回りして考え、選択肢を提示するパートナーです。

【基本姿勢】
- 押しつけない。選択肢を提示し、最終判断は必ずドライバーに委ねる
- 簡潔に話す。運転中なので1回の発言は3〜4文以内に収める
- 情報を羅列するのではなく、状況を解釈して自分の言葉で伝える
- 「〜してください」ではなく「〜しますか？」「〜はどうですか？」のように対等な口調で話す
- 敬語は使うが、堅すぎない。助手席に座っている頼れる友人のような距離感
- テンションは穏やかに。「！」は控えめにする

【ドライバーの情報】
- 車種：Mazda CX-8（全幅：1,840mm）
- 道幅が広い道・慣れた道を好む。狭い住宅街の抜け道は避けたい
- 渋滞で並んで待つのは嫌い。少し遠回りでも動いていたい
- 週末ドライブが多い（近所〜ショッピングモール、たまに1時間程度の遠出）
- 車内で音楽を聴く派
- 高速に乗るときは湾岸習志野ICをよく使う

【走行履歴（直近）】
1. 5/19（日）千葉市稲毛区 → Movix柏の葉
   - ルート：海浜大通り → 国道357号 → 湾岸習志野IC → 東関東道E51 → 高谷JCT → 外環C3 → 三郷JCT → 常磐道E6 → 柏IC
   - 所要時間：42分
   - 途中、外環C3で渋滞があり、手前で降りる迂回を選択（渋滞で待つより動きたい）
2. 5/12（日）千葉市稲毛区 → イオンモール幕張新都心
   - ルート：海浜大通り → 国道357号 → 下道のみ
   - 所要時間：18分
   - 近場なので高速は使わず
3. 5/5（日）千葉市稲毛区 → 昭和の森公園（千葉市緑区）
   - ルート：下道（大網街道）
   - 所要時間：30分
   - 公園なので急ぐ必要なし、ドライブ自体を楽しんだ

【現在の状況】
- 現在地：千葉市稲毛区（自宅）
- 現在時刻：日曜日の朝7:30
- 天候：晴れ

【目的地の性質を判断する基準】
- 映画館・コンサート → 開演時刻に遅れられない → 到着時刻の予測しやすいルート（高速優先）を提案し、開演時刻を確認する
- 公園・景勝地 → 急がない → 下道優先で景色の良い道を提案
- ショッピングモール → 適度に早く着きたい → 距離と混雑を考慮
- 飲食店 → 予約の有無を確認

【ルート提案のルール】
- 必ず2案以上を比較して提示する
- 各案の所要時間・距離の違いを簡潔に伝える
- 走行履歴から「この人ならこちらを選びそう」という案を推薦してよいが、決めつけない
- 未走行ルートを提案する場合は「初めての道になりますが」と一言添える

【渋滞時の対応】
- 渋滞を検知したら、まず状況を言葉で説明する（長さ、予測時間、伸びそうかどうか）
- 「渋滞に並ぶ」か「迂回する」かの選択肢を提示する
- 迂回した場合の到着時間の差も伝える
- このドライバーは渋滞待ちが嫌いだが、押しつけずに選ばせる

【目的地近接時】
- 商業施設の場合は、駐車場の入口・おすすめの階数まで案内する
- 「映画館に近いのはP6です」のように、目的に応じた具体的な情報を出す

【役割分担とデータの扱い（重要）】
あなた（MyWayNavi）の役割は、会話・意図の理解・状況の解釈・選択肢の提示です。
ルートの具体的な数値（所要時間・距離・渋滞の長さや予測時間）は、
アプリがGoogle Mapsから取得してあなたに提供します。

- これらの数値を、あなたが想像や推測で作ってはいけません
- アプリから「ルート情報」が提供されている場合のみ、その数値を使って説明してください
- まだルート情報が提供されていない場合は、数値を一切口にせず、
  「今ルートを調べますね」「ルートを確認します」とだけ伝えてください
- 提供されたデータの範囲を超える数値（「あと何分で着く」等）を勝手に補わないこと

【走行履歴の数値との混同に注意（重要）】
- 上記の【走行履歴（直近）】に含まれる所要時間・距離などの数値は、
  あくまで「このドライバーがどの道を好むか」という傾向を読むための参考情報です
- 今回ユーザーに提示するルートの数値（所要時間・距離）は、
  必ずアプリが渡す直近の[ルート情報]の数値だけを使ってください
- [ルート情報]がまだ渡されていない場合は、たとえ過去に走ったことのある
  目的地（例：Movix柏の葉など走行履歴にある場所）であっても、
  数値を一切口にせず「ルートを確認します」とだけ返してください
- 走行履歴の数値や、このプロンプト内の例文の数値を、
  今回の提示にそのまま転用してはいけません

アプリからのデータは、あなたへの入力の中に次のような形式で渡されます：
---
[ルート情報]
ルートA：（IC名）経由（高速優先）／所要（実際の分）／距離（実際のkm）／前回も走行
ルートB：（IC名）経由（下道多め）／所要（実際の分）／距離（実際のkm）／未走行
---
※括弧内にはアプリが渡した実データが入ります。この例文の括弧を自分で数字や地名で埋めないでください。
このデータが渡されたら、それを自分の言葉で、パートナーらしく噛み砕いて伝えてください。
データの数値は正確に使い、あなたが脚色するのは「言い回し」だけです。

【やってはいけないこと】
- 長文で話すこと（運転中に読めない）
- 1つのルートだけを提示して「これで行きましょう」と決めること
- ドライバーの選択を否定すること
- 走行履歴にない道を「いつもの道」と言うこと
- ルートの数値を自分で創作すること
"""

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatTurn(BaseModel):
    role: str
    text: str


class ChatRequest(BaseModel):
    message: str
    history: list[ChatTurn] = []


class ChatResponse(BaseModel):
    reply: str


class LatLng(BaseModel):
    lat: float
    lng: float


class CongestionEvent(BaseModel):
    id: str
    location_label: str
    length_km: float
    injected_delay_min: int
    note: str = ""


class RerouteRequest(BaseModel):
    current_location: LatLng
    destination: str
    congestion_event: CongestionEvent
    conversation_history: list[ChatTurn] = []


class EtaBreakdown(BaseModel):
    api_static_min: int
    injected_delay_min: int


class RouteOption(BaseModel):
    id: str
    label: str
    polyline: str
    eta_min: int
    eta_breakdown: EtaBreakdown


class RerouteResponse(BaseModel):
    reply: str
    action: str = "show_reroute"
    routes: list[RouteOption]
    source: str


def _turn_to_gemini_part(turn: ChatTurn) -> dict:
    return {"role": turn.role, "parts": [{"text": turn.text}]}


async def _call_gemini_with_retry(contents: list[dict]) -> dict:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEYが設定されていません")

    payload = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
    }
    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": GEMINI_API_KEY,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        for attempt in range(MAX_RETRIES + 1):
            try:
                response = await client.post(GEMINI_ENDPOINT, headers=headers, json=payload)
            except httpx.RequestError:
                raise HTTPException(status_code=502, detail="Geminiへの通信に失敗しました")

            if response.status_code not in RETRYABLE_STATUS_CODES:
                if response.status_code != 200:
                    raise HTTPException(
                        status_code=502,
                        detail=f"Gemini APIエラー（status: {response.status_code}）",
                    )
                return response.json()

            if attempt == MAX_RETRIES:
                raise HTTPException(
                    status_code=503,
                    detail="ただいま混み合っているようです。少し待ってもう一度お試しください",
                )

            await asyncio.sleep(2 ** attempt)

    # 到達しないが型チェッカー対応
    raise HTTPException(status_code=503, detail="ただいま混み合っているようです。少し待ってもう一度お試しください")


class RoutesApiError(Exception):
    """Routes APIの呼び出し失敗・期待形チェックNGを表す（/rerouteのfallback判定に使う）"""


async def _compute_route(
    origin: LatLng,
    destination: LatLng,
    via: LatLng | None = None,
) -> tuple[int, str]:
    """Routes API(computeRoutes)を呼び、(staticDuration秒, encodedPolyline)を返す。
    エラー・タイムアウト・routes空はRoutesApiErrorに正規化する。"""
    if not GOOGLE_MAPS_API_KEY:
        raise RoutesApiError("GOOGLE_MAPS_API_KEYが設定されていません")

    body: dict = {
        "origin": {"location": {"latLng": {"latitude": origin.lat, "longitude": origin.lng}}},
        "destination": {
            "location": {"latLng": {"latitude": destination.lat, "longitude": destination.lng}}
        },
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_UNAWARE",
        "polylineEncoding": "ENCODED_POLYLINE",
    }
    if via is not None:
        body["intermediates"] = [
            {"location": {"latLng": {"latitude": via.lat, "longitude": via.lng}}, "via": True}
        ]

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": ROUTES_FIELD_MASK,
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(ROUTES_API_ENDPOINT, headers=headers, json=body)
    except httpx.RequestError as e:
        raise RoutesApiError(f"Routes APIへの通信に失敗しました: {e}")

    if response.status_code != 200:
        raise RoutesApiError(f"Routes APIエラー（status: {response.status_code}）")

    data = response.json()
    routes = data.get("routes") or []
    if not routes:
        raise RoutesApiError("Routes APIがルートを返しませんでした")

    route = routes[0]
    duration_seconds = int(route.get("staticDuration", "0s").rstrip("s"))
    polyline = (route.get("polyline") or {}).get("encodedPolyline", "")
    if not polyline:
        raise RoutesApiError("Routes APIがpolylineを返しませんでした")

    return duration_seconds, polyline


def _build_congestion_prompt(
    event: CongestionEvent,
    route_stay_eta_min: int,
    route_detour_eta_min: int,
    injected_delay_min: int,
) -> str:
    diff = route_detour_eta_min - (route_stay_eta_min - injected_delay_min)
    return (
        "[渋滞情報]\n"
        f"- 渋滞地点：{event.location_label}\n"
        f"- 渋滞の長さ：約{event.length_km}km\n"
        f"- 通過予測：約{injected_delay_min}分、{event.note}\n"
        f"- ルート1（並ぶ）：このまま常磐道。早いが渋滞に停まる。到着{route_stay_eta_min}分後\n"
        f"- ルート2（迂回）：三郷中央ICで降りて三郷流山橋経由、流山ICで再流入。"
        f"到着{route_detour_eta_min}分後（約{diff:+d}分）だが停まらずスムーズ\n"
        "上記を運転者に簡潔に説明し、「並ぶ／迂回」のどちらにするか尋ねてください。判断は委ねること。"
    )


def _fixed_congestion_reply(
    event: CongestionEvent, route_stay_eta_min: int, route_detour_eta_min: int
) -> str:
    # 実際にlive応答した文面（source: "live"）の言い回しを踏襲した固定文。
    # fallback分岐ではGeminiを呼ばないため、数値以外はここで完全に固定する。
    return (
        f"{event.location_label}で約{event.length_km}kmほどの渋滞が発生しており、"
        f"通過に{event.injected_delay_min}分ほどかかる見込みです（{event.note}）。\n"
        f"このまま進むと{route_stay_eta_min}分後の到着になりますが、"
        "並ばず動ける迂回ルートもあります。\n"
        "三郷中央ICで一度降りて流山ICから再流入するルートなら、"
        f"距離は少し増えますが{route_detour_eta_min}分で到着できそうです。\n"
        "並ぶか迂回するか、どうしますか？"
    )


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    contents = [_turn_to_gemini_part(t) for t in req.history]
    contents.append({"role": "user", "parts": [{"text": req.message}]})

    data = await _call_gemini_with_retry(contents)

    candidates = data.get("candidates") or []
    if not candidates:
        raise HTTPException(status_code=502, detail="Geminiから応答が得られませんでした")

    parts = (candidates[0].get("content") or {}).get("parts") or []
    if not parts or not parts[0].get("text"):
        raise HTTPException(status_code=502, detail="Geminiの応答形式が不正です")

    return ChatResponse(reply=parts[0]["text"])


@app.post("/reroute", response_model=RerouteResponse)
async def reroute(req: RerouteRequest) -> RerouteResponse:
    event = req.congestion_event
    destination_point = LatLng(lat=MOVIX_KASHIWANOHA["lat"], lng=MOVIX_KASHIWANOHA["lng"])
    via_point = LatLng(
        lat=MISATO_NAGAREYAMA_BRIDGE_VIA["lat"], lng=MISATO_NAGAREYAMA_BRIDGE_VIA["lng"]
    )

    try:
        t1_seconds, route1_polyline = await _compute_route(
            req.current_location, destination_point
        )
        t2_seconds, route2_polyline = await _compute_route(
            req.current_location, destination_point, via=via_point
        )

        t1_min = -(-t1_seconds // 60)  # 秒→分（切り上げ）
        t2_min = -(-t2_seconds // 60)

        # 期待形チェック：viaが効いておらず直進とほぼ同形の疑い（差が3分未満）
        if (t2_min - t1_min) < 3:
            raise RoutesApiError("ルート2が迂回になっていない疑いがあるためfallback")

        route_stay_eta_min = t1_min + event.injected_delay_min
        route_detour_eta_min = t2_min

        prompt = _build_congestion_prompt(
            event, route_stay_eta_min, route_detour_eta_min, event.injected_delay_min
        )
        contents = [_turn_to_gemini_part(t) for t in req.conversation_history]
        contents.append({"role": "user", "parts": [{"text": prompt}]})
        gemini_data = await _call_gemini_with_retry(contents)

        candidates = gemini_data.get("candidates") or []
        parts = (candidates[0].get("content") or {}).get("parts") or [] if candidates else []
        reply = parts[0]["text"] if parts and parts[0].get("text") else None
        if not reply:
            raise RoutesApiError("Geminiから応答が得られなかったためfallback")

        return RerouteResponse(
            reply=reply,
            routes=[
                RouteOption(
                    id="route_stay",
                    label="並ぶ（このまま常磐道）",
                    polyline=route1_polyline,
                    eta_min=route_stay_eta_min,
                    eta_breakdown=EtaBreakdown(
                        api_static_min=t1_min, injected_delay_min=event.injected_delay_min
                    ),
                ),
                RouteOption(
                    id="route_detour",
                    label="迂回（三郷中央IC→三郷流山橋→流山IC）",
                    polyline=route2_polyline,
                    eta_min=route_detour_eta_min,
                    eta_breakdown=EtaBreakdown(api_static_min=t2_min, injected_delay_min=0),
                ),
            ],
            source="live",
        )
    except RoutesApiError:
        # fallback：Gemini呼び出しも行わず固定値・固定文で即応答する
        reply = _fixed_congestion_reply(
            event, FALLBACK_STAY_ETA_MIN, FALLBACK_DETOUR_ETA_MIN
        )
        return RerouteResponse(
            reply=reply,
            routes=[
                RouteOption(
                    id="route_stay",
                    label="並ぶ（このまま常磐道）",
                    polyline=FALLBACK_STAY_POLYLINE,
                    eta_min=FALLBACK_STAY_ETA_MIN,
                    eta_breakdown=EtaBreakdown(
                        api_static_min=FALLBACK_STAY_ETA_MIN - event.injected_delay_min,
                        injected_delay_min=event.injected_delay_min,
                    ),
                ),
                RouteOption(
                    id="route_detour",
                    label="迂回（三郷中央IC→三郷流山橋→流山IC）",
                    polyline=FALLBACK_DETOUR_POLYLINE,
                    eta_min=FALLBACK_DETOUR_ETA_MIN,
                    eta_breakdown=EtaBreakdown(
                        api_static_min=FALLBACK_DETOUR_ETA_MIN, injected_delay_min=0
                    ),
                ),
            ],
            source="fallback",
        )
