import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// 現在 gemini-3.5-flash がGoogle側の高負荷で503を返すことがあるため、
// 一時的に gemini-3.1-flash-lite に切り替えている。
// 503が落ち着いたら 'gemini-3.5-flash' に戻すこと。
const String geminiModel = 'gemini-3.1-flash-lite';

// false: Flutterから直接Gemini APIを呼ぶ（開発用）
// true: 自前のバックエンド（Cloud Run上のFastAPI /chat）経由で呼ぶ（デモ・提出用）
const bool useBackend = true;

// Cloud RunにデプロイしたバックエンドのURL
const String backendBaseUrl =
    'https://mywaynavi-backend-698507727621.asia-northeast1.run.app';

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);

  @override
  String toString() => message;
}

const String _systemPrompt = '''
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
- 各案の所要時間・距離・高速料金の違いを簡潔に伝える
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
ルートの具体的な数値（所要時間・距離・高速料金・渋滞の長さや予測時間）は、
アプリがGoogle Mapsから取得してあなたに提供します。

- これらの数値を、あなたが想像や推測で作ってはいけません
- アプリから「ルート情報」が提供されている場合のみ、その数値を使って説明してください
- まだルート情報が提供されていない場合は、数値を一切口にせず、
  「今ルートを調べますね」「ルートを確認します」とだけ伝えてください
- 提供されたデータの範囲を超える数値（「あと何分で着く」等）を勝手に補わないこと

アプリからのデータは、あなたへの入力の中に次のような形式で渡されます：
---
[ルート情報]
ルートA：湾岸習志野IC経由（高速優先）／所要45分／距離52km／高速料金1,500円／前回も走行
ルートB：京葉IC経由（下道多め）／所要55分／距離54km／高速料金1,000円／未走行
---
このデータが渡されたら、それを自分の言葉で、パートナーらしく噛み砕いて伝えてください。
データの数値は正確に使い、あなたが脚色するのは「言い回し」だけです。

【やってはいけないこと】
- 長文で話すこと（運転中に読めない）
- 1つのルートだけを提示して「これで行きましょう」と決めること
- ドライバーの選択を否定すること
- 走行履歴にない道を「いつもの道」と言うこと
- ルートの数値を自分で創作すること
''';

class _ChatTurn {
  final String role;
  final String text;
  const _ChatTurn(this.role, this.text);

  Map<String, dynamic> toGeminiJson() => {
        'role': role,
        'parts': [
          {'text': text}
        ],
      };

  Map<String, dynamic> toBackendJson() => {
        'role': role,
        'text': text,
      };
}

class GeminiService {
  static const _maxRetries = 3;
  static final Uri _directEndpoint = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
  );
  static final Uri _backendChatEndpoint = Uri.parse('$backendBaseUrl/chat');

  final List<_ChatTurn> _history = [];

  void clearHistory() {
    _history.clear();
  }

  Future<String> sendMessage(String text) async {
    final replyText = useBackend
        ? await _sendViaBackend(text)
        : await _sendDirectToGemini(text);

    _history.add(_ChatTurn('user', text));
    _history.add(_ChatTurn('model', replyText));

    return replyText;
  }

  Future<String> _sendDirectToGemini(String text) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw const GeminiException('GEMINI_API_KEYが設定されていません');
    }

    final turnsForRequest = [..._history, _ChatTurn('user', text)];
    final body = json.encode({
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      'contents': turnsForRequest.map((t) => t.toGeminiJson()).toList(),
    });

    final response = await _postWithRetry(
      () => http.post(
        _directEndpoint,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: body,
      ),
    );

    final data = json.decode(response.body);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const GeminiException('Geminiから応答が得られませんでした');
    }

    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty || parts[0]['text'] == null) {
      throw const GeminiException('Geminiの応答形式が不正です');
    }

    return parts[0]['text'] as String;
  }

  Future<String> _sendViaBackend(String text) async {
    final body = json.encode({
      'message': text,
      'history': _history.map((t) => t.toBackendJson()).toList(),
    });

    final response = await _postWithRetry(
      () => http.post(
        _backendChatEndpoint,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ),
    );

    final data = json.decode(response.body);
    final reply = data['reply'];
    if (reply == null || reply is! String || reply.isEmpty) {
      throw const GeminiException('バックエンドからの応答が不正です');
    }

    return reply;
  }

  Future<http.Response> _postWithRetry(
    Future<http.Response> Function() request,
  ) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      http.Response response;
      try {
        response = await request();
      } catch (e) {
        throw const GeminiException('通信に失敗しました');
      }

      final isRetryable =
          response.statusCode == 503 || response.statusCode == 429;
      if (!isRetryable) {
        if (response.statusCode != 200) {
          throw GeminiException(
            'エラーが発生しました（status: ${response.statusCode}）',
          );
        }
        return response;
      }

      if (attempt == _maxRetries) {
        throw const GeminiException(
          'ただいま混み合っているようです。少し待ってもう一度お試しください',
        );
      }

      await Future.delayed(Duration(seconds: 1 << attempt));
    }

    throw const GeminiException(
      'ただいま混み合っているようです。少し待ってもう一度お試しください',
    );
  }
}
