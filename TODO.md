# TODO — ruby-knowledge-db

## 現在の DB 状態（2026-04-02 時点）

| ソース | 件数 | 備考 |
|--------|------|------|
| rurema/doctree:ruby3.3 | 1,559 | ✅ 完了 |
| picoruby/picoruby:docs | 177 | ✅ 完了 |
| picoruby/picoruby:trunk/article | 77 | ✅ MD ファイル手動 import |
| picoruby/picoruby:trunk/diff | 6 | trunk-changes-diary 由来 |
| ruby/ruby trunk | 0 | ❌ 要検討 |
| mruby/mruby trunk | 0 | ❌ 要検討 |

---

## 要検討

### trunk 系データソースの方針再考

`picoruby_trunk` / `cruby_trunk` / `mruby_trunk` は `trunk-changes-diary` を使ってコミット解説を生成するが、
**AI 生成にトークンコストが高い**。以下を検討：

- [ ] trunk 系: AI 解説生成なし → raw commit log/diff のみ収集に変える？
- [ ] ruby/ruby・mruby/mruby: shallow clone して収集する価値があるか？
- [ ] picoruby_trunk: 今後は `import_md_files.rb` で手動 import に移行する？
  - `/private/tmp/.../picoruby-trunk-changes` 配下の md ファイルが蓄積される運用
  - `scripts/import_md_files.rb <dir>` で随時 import

### データ拡充候補

- [ ] mruby-c/mruby-c のドキュメント・変更履歴
- [ ] rurema の他バージョン（ruby3.4 等）
- [ ] RubyGems の人気 gem の README/ドキュメント

---

## 運用

### 手動実行

```bash
# 通常更新（picoruby_docs / rurema の差分）
bundle exec ruby scripts/update_all.rb

# MD ファイル一括 import
bundle exec ruby scripts/import_md_files.rb <dir> [source]
```

### MCP サーバー

```bash
# Claude Code (user-wide): 登録済み
claude mcp list  # chiebukuro-mcp ✓ Connected

# Claude Desktop: claude_desktop_config.json に登録済み
# scripts/start_mcp.sh 経由
```

---

## 技術的負債・改善候補

- [ ] リモート MCP サーバー（Streamable HTTP / Rack + Puma）
- [ ] エラー通知（Orchestrator の errors を Slack 等へ）
- [ ] `import_md_files.rb` の since 対応（新規ファイルのみ import）
