# Design: Workflow化・モデル最適化

## 問題

### コンテキスト汚染による twin dispatch
`/ruby-knowledge-db` コマンドはメインセッションでルーティングを行う。長いセッションでは前回の実行結果・SINCE/BEFORE・PRE state が蓄積し、AIの「in-flight セッションは1つのみ」ルールが記憶ベースになる。実績ログでは同日に3セッションが立ち上がるケースが確認されている（`rkdb-default-20260603-*`）。

### `consistent: false` の発生源
`PipelinePlan` の矛盾チェック6条件（WIP残骸・esa衝突・不正区間・bookmark欠落・未来日付・複数WIP）はほぼすべて Claude Code 自身の twin dispatch と partial completion バグが原因。外部起因（ネットワーク障害等）の実績はゼロ。`consistent: false` = 異常 = 即中断・人間へエスカレーション。

### モデル品質の問題
- 記事生成（Claude CLI）が `"sonnet"` 固定（`trunk_changes.rb:187`）。esa に投稿される成果物は不可逆であり品質ミスは修正コストが高い
- inspect-agent・run-agent はモデル指定なしで親セッションの Sonnet を継承。read-only の単純タスクにも Sonnet を使っている

---

## 設計

### 1. Daily pipeline → Workflow 化

`.claude/workflows/rkdb-daily.js` として保存。JS スクリプトが中間状態（plan JSON・session name・log path・PRE state）をスクリプト変数に保持し、メインセッションのコンテキストに積まない。

**Workflow ステージ：**

| Stage | 担当 | Model | Effort | 処理 |
|-------|------|-------|--------|------|
| 1. preflight | agent | Haiku | low | `rake plan` JSON 取得・`consistent` 判定 |
| 2. launch | agent | Haiku | low | lockfile 確認・tmux 起動・PRE state 取得 |
| 3. wait | script loop | — | — | 30秒ポーリングで `DONE:` sentinel 待機 |
| 4. postcheck | agent | **Opus** | high | ログ分析・state delta・pollution scan・結果報告 |

**中断ルール：**
- Stage 1: `consistent: false` → 即 abort。`contradiction_reasons` を表示して「手動修正してから再実行してください」
- Stage 4: `DONE: exit≠0` → 即 abort。ログ末尾50行を表示して人間へエスカレーション
- `RKDB_FORCE` は Workflow 経路には存在しない（escape hatch = ターミナルから手動 `bundle exec rake RKDB_FORCE=1`）

**Twin dispatch 防止：**
- Workflow ランタイム自体がシーケンシャル実行 → AIの記憶不要
- Stage 2 が `tmp/longrun/RUNNING` lockfile を書き込み、Stage 4 完了後に削除
- Stage 1 で lockfile 存在を検出したら abort「前回パイプラインが進行中です」

### 2. 記事生成モデル変更（trunk-changes-diary）

`Rakefile` の `build_trunk_collector` に `model:` を追加：

```ruby
gen = ContentGenerator.new(
  repo: source_cfg['repo'],
  prompt_supplement: source_cfg['prompt_supplement'],
  model: ENV.fetch('RKDB_ARTICLE_MODEL', 'opus')
)
```

デフォルトを `opus` に変更。後退させたい場合は `RKDB_ARTICLE_MODEL=sonnet` で上書き可能。

### 3. エージェント frontmatter モデル指定

| エージェント | 変更 | 理由 |
|-------------|------|------|
| `ruby-knowledge-db-inspect.md` | `model: haiku` 追加 | read-only・構造的コマンド実行のみ |
| `ruby-knowledge-db-run.md` | PLAN mode: `model: haiku`、EXECUTE foreground: `model: opus` | PLANはJSON転送のみ、EXECUTEは本番副作用あり |

run-agent は単一ファイルで複数モードを扱うため frontmatter は `model: opus` とする。Workflow 経由の daily pipeline では preflight Stage 1 が inspect-agent（Haiku）で `rake plan` を取得するため、run-agent の PLAN mode は daily pipeline では呼ばれない。cleanup の PLAN mode（稀な操作）は Opus が動くが許容範囲。

### 4. 変更しない部分

- inspect-agent の呼び出し口（`/ruby-knowledge-db` コマンドの inspect フロー）
- run-agent の PLAN → CONFIRMED cleanup フロー（HITL が本質的に必要な操作）
- `PipelinePlan`・`EsaPreflight`・`TrunkBookmark` の Ruby 実装（変更不要）

---

## モデル割り当て全体図

```
[esa 記事本文生成]  Claude CLI  --model opus          ← 不可逆成果物、最高品質
[Workflow preflight] Haiku                             ← JSON parse のみ
[Workflow launch]    Haiku                             ← 機械的 tmux 起動
[Workflow postcheck] Opus  effort=high                ← 複合ログ分析、誤報告リスク高
[inspect-agent]      Haiku                             ← read-only、単純コマンド
[run-agent cleanup]  Opus  effort=high                ← 本番削除・結果判定
```

---

## 実装順序

1. `ruby-knowledge-db-inspect.md` に `model: haiku` 追加（即効・独立）
2. `Rakefile` に `RKDB_ARTICLE_MODEL` 環境変数追加、デフォルト `opus`（trunk-changes-diary は変更なし）
3. `run-agent` frontmatter に `model: opus` 追加
4. Workflow スクリプト `.claude/workflows/rkdb-daily.js` 作成・保存
5. `/ruby-knowledge-db` コマンドの pipeline フローを Workflow 呼び出しに切り替え
