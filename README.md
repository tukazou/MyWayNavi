# MyWayNavi 🚗

> ナビじゃない、ドライビングパートナー

## 概要

MyWayNaviは、ドライバーの走行履歴・好み・車種を学習し、"自分流"のルートを提案するAIナビエージェントです。

今のナビは「案内しかしない」。MyWayNaviは、何も言わなくても好きな道を選んでくれる、助手席に賢い人が乗っているような体験を提供します。

## DevOps × AI Agent Hackathon 2026

本プロダクトは、[DevOps × AI Agent Hackathon 2026](https://findy.notion.site/devops-ai-agent-hackathon-2026) への提出作品です。

- 主催：ファインディ株式会社
- メインスポンサー：グーグル・クラウド・ジャパン
- 提出締め切り：2026年7月10日（金）23:59

## 技術スタック

| レイヤー | 技術 |
|---|---|
| バックエンド | Python + FastAPI |
| AI | Gemini API（Vertex AI / Agent Platform） |
| 地図・ルート | Google Maps API |
| デプロイ | Cloud Run |
| CI/CD | GitHub Actions → Cloud Run |
| フロントエンド | HTML / CSS / JavaScript |

## セットアップ

```bash
# リポジトリのクローン
git clone https://github.com/YOUR_USERNAME/mywaynavi.git
cd mywaynavi

# 依存関係のインストール
pip install -r requirements.txt

# 環境変数の設定
cp .env.example .env
# .envにGoogle CloudのプロジェクトIDなどを設定

# ローカル起動
uvicorn main:app --reload
```

## 環境変数

```
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_MAPS_API_KEY=your-maps-api-key
```

## ディレクトリ構成

```
mywaynavi/
├── main.py              # FastAPIエントリーポイント
├── agent/               # Geminiエージェント関連
│   ├── gemini.py        # Gemini API呼び出し
│   └── prompt.py        # プロンプト管理
├── routes/              # APIルーター
├── data/                # 走行履歴データ（モック）
├── static/              # フロントエンド
├── requirements.txt
├── Dockerfile
├── .env.example
├── .gitignore
└── docs/
    └── 企画書.md
```

## 注意事項

- `.env`ファイルはGitHubにコミットしないこと
- サービスアカウントのJSONキーはGitHubにコミットしないこと
