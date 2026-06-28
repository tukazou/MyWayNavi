import asyncio
import os

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

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
