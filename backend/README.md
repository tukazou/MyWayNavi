# MyWayNavi backend

Gemini呼び出し用の最小バックエンド（FastAPI）。`/chat` のみを提供し、`/route`（Maps）は今のところFlutterから直接呼ぶ。

## ローカルでの起動方法

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export GEMINI_API_KEY=your-gemini-api-key
export GEMINI_MODEL=gemini-3.1-flash-lite   # 任意。省略時はこの値がデフォルト
export ALLOWED_ORIGINS=*                     # 任意。省略時は*

uvicorn main:app --reload --port 8080
```

## 動作確認

```bash
curl http://localhost:8080/health

curl -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "こんにちは。あなたは何ができますか?", "history": []}'
```

2ターン目以降は`history`に過去の発言を `{"role": "user"|"model", "text": "..."}` の配列で渡す。

## Dockerでのローカル起動

```bash
cd backend
docker build -t mywaynavi-backend .
docker run -p 8080:8080 -e GEMINI_API_KEY=your-gemini-api-key mywaynavi-backend
```

## Cloud Runへのデプロイ（手動・初回セットアップ）

CI/CD（`.github/workflows/deploy-backend.yml`）が自動デプロイするが、それ以前に以下を手動で用意する必要がある：

1. GCPプロジェクトでCloud Run API・Artifact Registry APIを有効化
2. デプロイ用サービスアカウントを作成し、Cloud Run管理者・Artifact Registry書き込み等のロールを付与
3. そのサービスアカウントの鍵（JSON）を発行し、GitHub Secretsに `GCP_SA_KEY` として登録
   （Workload Identity連携を使う場合はワークフローを書き換えて鍵発行は不要にできる）
4. 以下をGitHub Secretsに登録：
   - `GCP_PROJECT_ID`
   - `GCP_REGION`（例: `asia-northeast1`）
   - `CLOUD_RUN_SERVICE`（Cloud Runのサービス名）
   - `ARTIFACT_REPO`（Artifact Registryのリポジトリ名。事前に`gcloud artifacts repositories create`で作成）
5. Gemini APIキーはワークフローやリポジトリには置かず、Secret Managerに登録した上でCloud Run側の環境変数として設定する（例: `gcloud run deploy ... --set-secrets=GEMINI_API_KEY=gemini-api-key:latest`）
6. Flutter側（`lib/services/gemini_service.dart`）の `backendBaseUrl` を、デプロイ後のCloud Run URLに差し替え、`useBackend` を `true` にする
