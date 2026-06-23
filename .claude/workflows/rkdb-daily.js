export const meta = {
  name: 'rkdb-daily',
  description: 'ruby-knowledge-db daily pipeline: preflight → launch tmux → wait → postcheck',
  phases: [
    { title: 'Preflight', detail: 'lockfile check → rake plan → consistent 判定' },
    { title: 'Launch',    detail: 'lockfile write → PRE stats → tmux 起動' },
    { title: 'Wait',      detail: '30秒ポーリング、120分タイムアウト' },
    { title: 'Postcheck', detail: 'ログ分析 → delta 計算 → pollution scan → lockfile 削除' },
  ],
}

const REPO = '/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db'

// ── Stage 1: Preflight (model: haiku) ──────────────────────────────────────

phase('Preflight')

const PREFLIGHT_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status:               { type: 'string', enum: ['ok', 'locked', 'inconsistent'] },
    since:                { type: 'string', description: 'YYYY-MM-DD' },
    before:               { type: 'string', description: 'YYYY-MM-DD' },
    contradiction_reasons: { type: 'array', items: { type: 'string' } },
  },
}

const preflight = await agent(
  `You are doing a pre-flight check for the ruby-knowledge-db daily pipeline.

Working directory: ${REPO}

Step 1: Check lockfile
Run: test -f ${REPO}/tmp/longrun/RUNNING
If exit code is 0 (file exists), return JSON: { "status": "locked" }

Step 2: Run rake plan
Run: cd ${REPO} && APP_ENV=production bundle exec rake plan
Parse the JSON output.
If "consistent" is false, return JSON:
  { "status": "inconsistent", "contradiction_reasons": [array from JSON] }
If "consistent" is true, return JSON:
  { "status": "ok", "since": "<since from JSON>", "before": "<before from JSON>" }`,
  { label: 'preflight', phase: 'Preflight', model: 'haiku', schema: PREFLIGHT_SCHEMA }
)

if (!preflight) {
  log('ERROR: preflight agent failed')
  return { status: 'error', reason: 'preflight agent failed' }
}

if (preflight.status === 'locked') {
  log('ABORTED: 前回パイプラインが実行中です。tmp/longrun/RUNNING を確認してから再実行してください。')
  return { status: 'aborted', reason: 'lockfile exists' }
}

if (preflight.status === 'inconsistent') {
  const reasons = (preflight.contradiction_reasons || []).join(', ')
  log(`ABORTED: 異常検出: ${reasons}。手動で修正してから再実行してください。`)
  return { status: 'aborted', reason: 'inconsistent', contradiction_reasons: preflight.contradiction_reasons }
}

const { since, before } = preflight
log(`Preflight OK — SINCE=${since} BEFORE=${before}`)

// ── Stage 2: Launch (model: haiku) ─────────────────────────────────────────

phase('Launch')

const LAUNCH_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status:      { type: 'string', enum: ['ok', 'rbenv_error'] },
    session:     { type: 'string' },
    logPath:     { type: 'string' },
    preMemories: { type: 'integer' },
    preBookmark: { type: 'string' },
    rbenvCheck:  { type: 'string' },
  },
}

const launch = await agent(
  `You are launching the ruby-knowledge-db pipeline in a detached tmux session.

Working directory: ${REPO}
SINCE: ${since}
BEFORE: ${before}

Step 1: Create lockfile directory and write lockfile
Run: mkdir -p ${REPO}/tmp/longrun
Run: echo running > ${REPO}/tmp/longrun/RUNNING

Step 2: Get pre-run memory count
Run: cd ${REPO} && APP_ENV=production bundle exec rake db:stats
Extract the "memories total: N" line. Store N as preMemories integer.

Step 3: Read bookmark
Run: cat ${REPO}/db/last_run.yml
Store the full content as preBookmark string.

Step 4: Generate timestamp and paths
Run: date +%Y%m%d-%H%M%S
Use the output as TIMESTAMP.
session = "rkdb-default-TIMESTAMP"
logPath = "${REPO}/tmp/longrun/rkdb-default-TIMESTAMP.log"

Step 5: Launch detached tmux session
Run exactly this command (substituting SINCE, BEFORE, LOG, SESSION with actual values):
  tmux new-session -d -s SESSION 'bash -c "cd ${REPO}; export PATH=$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH; { echo ENV which bundle: $(which bundle); ruby -v; } > LOG 2>&1; APP_ENV=production SINCE=SINCE BEFORE=BEFORE bundle exec rake >> LOG 2>&1; echo DONE: exit=$? finished_at=$(date -Iseconds) >> LOG"'

Step 6: Wait 3 seconds then verify rbenv
Run: sleep 3 && head -2 LOG
Check if the output contains "/usr/bin/bundle". If it does, return: { "status": "rbenv_error", "rbenvCheck": "<first 2 lines>" }

If all OK, return:
{
  "status": "ok",
  "session": "SESSION",
  "logPath": "LOG",
  "preMemories": preMemories,
  "preBookmark": "full content of last_run.yml",
  "rbenvCheck": "<first 2 lines of log>"
}`,
  { label: 'launch', phase: 'Launch', model: 'haiku', schema: LAUNCH_SCHEMA }
)

if (!launch) {
  log('ERROR: launch agent failed')
  return { status: 'error', reason: 'launch agent failed', since, before }
}

if (launch.status === 'rbenv_error') {
  log(`ABORTED: rbenv 設定が失敗しました。ログ: ${launch.rbenvCheck}`)
  return { status: 'aborted', reason: 'rbenv error', rbenvCheck: launch.rbenvCheck }
}

const { session, logPath, preMemories, preBookmark } = launch
log(`Launched tmux session: ${session}`)
log(`Log: ${logPath}`)
log(`PRE memories: ${preMemories}`)

// ── Stage 3: Wait (polling loop) ───────────────────────────────────────────

phase('Wait')

const POLL_SCHEMA = {
  type: 'object',
  required: ['done'],
  properties: {
    done:     { type: 'boolean' },
    exitCode: { type: 'string' },
  },
}

const POLL_INTERVAL_MS = 30 * 1000
const TIMEOUT_MS       = 120 * 60 * 1000
const startTime        = Date.now()
let done               = false
let exitCode           = null

while (!done) {
  if (Date.now() - startTime > TIMEOUT_MS) {
    log(`パイプライン完了待ちがタイムアウトしました (120分)。${logPath} を確認してください。`)
    return { status: 'timeout', logPath, session, since, before }
  }

  await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL_MS))

  const poll = await agent(
    `Check if the ruby-knowledge-db pipeline has finished.

Read the log file: ${logPath}
Look for a line that starts with "DONE:".
If found, extract the exit code from "exit=N" on that line.
Return: { "done": true, "exitCode": "N" }
If not found, return: { "done": false }`,
    { label: 'poll', phase: 'Wait', model: 'haiku', schema: POLL_SCHEMA }
  )

  if (poll?.done) {
    done     = true
    exitCode = poll.exitCode
    log(`Pipeline finished with exit code: ${exitCode}`)
  } else {
    const elapsed = Math.round((Date.now() - startTime) / 60000)
    log(`Still running... (${elapsed}m elapsed)`)
  }
}

// ── Stage 4: Postcheck (model: claude-opus-4-8) ────────────────────────────

phase('Postcheck')

const POSTCHECK_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status:        { type: 'string' },
    postMemories:  { type: 'integer' },
    delta:         { type: 'integer' },
    esaPosts:      { type: 'string' },
    failures:      { type: 'string' },
    pollutionScan: { type: 'string' },
    esaDuplicates: { type: 'string' },
    logTail:       { type: 'string' },
  },
}

const postcheck = await agent(
  `You are doing a post-run check for the ruby-knowledge-db daily pipeline.

Working directory: ${REPO}
Log file: ${logPath}
Pipeline exit code: ${exitCode}
PRE memories: ${preMemories}
Session: ${session}

Step 1: Handle non-zero exit
If exit code is not "0":
  - Run: rm -f ${REPO}/tmp/longrun/RUNNING
  - Run: tail -50 ${logPath}
  - Return: { "status": "failed", "logTail": "<last 50 lines>" }

Step 2: Get post-run stats
Run: cd ${REPO} && APP_ENV=production bundle exec rake db:stats
Extract "memories total: N". Store as postMemories.

Step 3: Scan for pollution
Run: cd ${REPO} && APP_ENV=production bundle exec rake db:scan_pollution
Store full output as pollutionScan.

Step 4: Find ESA duplicates
Run: cd ${REPO} && APP_ENV=production bundle exec rake esa:find_duplicates
Store full output as esaDuplicates.

Step 5: Extract from log
Run: grep "esa: #" ${logPath} (ESA post lines)
Run: grep "ERROR in update:" ${logPath} (failure lines)
Run: grep "\\[trunk-changes\\]" ${logPath} (provenance lines)

Step 6: Delete lockfile
Run: rm -f ${REPO}/tmp/longrun/RUNNING

Step 7: Compute delta = postMemories - ${preMemories}

Return JSON:
{
  "status": "ok",
  "postMemories": postMemories,
  "delta": delta,
  "esaPosts": "<grep output or 'なし'>",
  "failures": "<grep output or 'なし'>",
  "pollutionScan": "<rake output>",
  "esaDuplicates": "<rake output>"
}`,
  { label: 'postcheck', phase: 'Postcheck', model: 'claude-opus-4-8', schema: POSTCHECK_SCHEMA }
)

if (!postcheck) {
  log('ERROR: postcheck agent failed')
  return { status: 'error', reason: 'postcheck agent failed', session, logPath }
}

if (postcheck.status === 'failed') {
  log(`パイプライン異常終了 (exit=${exitCode})。ログ末尾:\n${postcheck.logTail}`)
  return { status: 'pipeline_failed', exitCode, logPath, session, logTail: postcheck.logTail }
}

const { postMemories, delta, esaPosts, failures, pollutionScan, esaDuplicates } = postcheck

log(`=== rkdb-daily 完了 ===`)
log(`Session:    ${session}`)
log(`Memories:   ${preMemories} → ${postMemories} (+${delta})`)
log(`ESA posts:  ${esaPosts}`)
log(`Failures:   ${failures}`)
log(`Pollution:  ${pollutionScan}`)
log(`Duplicates: ${esaDuplicates}`)
log(`PRE bookmark:\n${preBookmark}`)

return {
  status:        'ok',
  session,
  since,
  before,
  preMemories,
  postMemories,
  delta,
  esaPosts,
  failures,
  pollutionScan,
  esaDuplicates,
  preBookmark,
}
