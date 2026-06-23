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

const REPO     = '/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db'
const LOCKFILE = `${REPO}/tmp/longrun/RUNNING`

// ── Stage 1: Preflight (model: haiku) ──────────────────────────────────────

phase('Preflight')

const PREFLIGHT_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status:                { type: 'string', enum: ['ok', 'locked', 'inconsistent'] },
    since:                 { type: 'string', description: 'YYYY-MM-DD' },
    before:                { type: 'string', description: 'YYYY-MM-DD' },
    contradiction_reasons: { type: 'array', items: { type: 'string' } },
  },
}

const preflight = await agent(
  `You are doing a pre-flight check for the ruby-knowledge-db daily pipeline.

Working directory: ${REPO}

Step 1: Check lockfile
Run: test -f ${LOCKFILE}
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
// Lockfile is written by JS here so cleanup is always possible on error.

phase('Launch')

// Generate timestamp and paths in JS so the tmux command is fully resolved.
const now = new Date()
const ts  = now.getFullYear().toString() +
  String(now.getMonth() + 1).padStart(2, '0') +
  String(now.getDate()).padStart(2, '0') +
  '-' +
  String(now.getHours()).padStart(2, '0') +
  String(now.getMinutes()).padStart(2, '0') +
  String(now.getSeconds()).padStart(2, '0')

const session = `rkdb-default-${ts}`
const logPath = `${REPO}/tmp/longrun/${session}.log`

// Construct the fully-resolved tmux command in JS.
// Shell variables ($HOME, $PATH, $?, $(…)) are escaped so they are NOT
// expanded by JavaScript but ARE expanded by the inner bash -c shell.
const tmuxCmd = `tmux new-session -d -s ${session} 'bash -c "cd ${REPO}; export PATH=\$HOME/.rbenv/shims:\$HOME/.rbenv/bin:\$PATH; { echo ENV which bundle: \$(which bundle); ruby -v; } > ${logPath} 2>&1; APP_ENV=production SINCE=${since} BEFORE=${before} bundle exec rake >> ${logPath} 2>&1; echo DONE: exit=\$? finished_at=\$(date -Iseconds) >> ${logPath}"'`

// Write lockfile in JS so we can always clean it up on error.
const lockSetup = await agent(
  `Write the lockfile and create its directory.
Run: mkdir -p ${REPO}/tmp/longrun
Run: echo running > ${LOCKFILE}
Return JSON: { "done": true }`,
  { label: 'lockfile-write', phase: 'Launch', model: 'haiku', schema: { type: 'object', required: ['done'], properties: { done: { type: 'boolean' } } } }
)

if (!lockSetup?.done) {
  log('ERROR: could not write lockfile')
  return { status: 'error', reason: 'lockfile write failed', since, before }
}

const LAUNCH_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status:      { type: 'string', enum: ['ok', 'rbenv_error'] },
    preMemories: { type: 'integer' },
    preBookmark: { type: 'string' },
    rbenvCheck:  { type: 'string' },
  },
}

const launch = await agent(
  `You are launching the ruby-knowledge-db pipeline in a detached tmux session.

Working directory: ${REPO}

Step 1: Get pre-run memory count
Run: cd ${REPO} && APP_ENV=production bundle exec rake db:stats
Extract the "memories total: N" line. Store N as preMemories integer.

Step 2: Read bookmark
Run: cat ${REPO}/db/last_run.yml
Store the full content as preBookmark string.

Step 3: Launch detached tmux session
Run this exact command:
  ${tmuxCmd}

Step 4: Wait 3 seconds then verify rbenv
Run: sleep 3 && head -2 ${logPath}
If the output contains "/usr/bin/bundle", return: { "status": "rbenv_error", "rbenvCheck": "<first 2 lines>" }

If all OK, return:
{
  "status": "ok",
  "preMemories": <integer>,
  "preBookmark": "<full content of last_run.yml>",
  "rbenvCheck": "<first 2 lines of log>"
}`,
  { label: 'launch', phase: 'Launch', model: 'haiku', schema: LAUNCH_SCHEMA }
)

if (!launch || launch.status === 'rbenv_error') {
  // Clean up lockfile before aborting.
  await agent(
    `Delete the lockfile: run rm -f ${LOCKFILE}. Return JSON: { "done": true }`,
    { label: 'lockfile-cleanup', phase: 'Launch', model: 'haiku', schema: { type: 'object', required: ['done'], properties: { done: { type: 'boolean' } } } }
  )
  if (!launch) {
    log('ERROR: launch agent failed — lockfile cleaned up')
    return { status: 'error', reason: 'launch agent failed', since, before }
  }
  log(`ABORTED: rbenv 設定が失敗しました。ログ: ${launch.rbenvCheck}`)
  return { status: 'aborted', reason: 'rbenv error', rbenvCheck: launch.rbenvCheck }
}

const { preMemories, preBookmark } = launch
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
    // Leave RUNNING in place — tmux session may still be running.
    log(`パイプライン完了待ちがタイムアウトしました (120分)。${logPath} を確認し、完了後に tmp/longrun/RUNNING を手動で削除してから再実行してください。`)
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
    status:        { type: 'string', enum: ['ok', 'failed'] },
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
  - Run: rm -f ${LOCKFILE}
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
Run: grep "esa: #" ${logPath}
Run: grep "ERROR in update:" ${logPath}
Run: grep "\\[trunk-changes\\]" ${logPath}

Step 6: Delete lockfile
Run: rm -f ${LOCKFILE}

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
}
