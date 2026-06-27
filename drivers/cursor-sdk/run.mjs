/**
 * drivers/cursor-sdk/run.mjs — Cursor SDK driver (Driver C) for skeleton-parallel
 *
 * Implements the ExecutionDriver contract (spec §8.2) using @cursor/sdk.
 * `CURSOR_API_KEY` is read from the environment and never logged.
 * `PROJECT_ROOT` is enforced via Agent's `local.cwd` option.
 *
 * CLI usage:
 *   node run.mjs <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
 *
 * Exit codes (per spec §8.2):
 *   0 — success
 *   1 — agent error (run failed, CURSOR_API_KEY not set)
 *   2 — quota / rate-limit exhausted → caller applies quota_retry policy
 *   3 — fatal (missing required arg, prompt file not found, SDK not installed)
 */

// ── Standard library imports (always available) ───────────────────────────
import { createWriteStream, mkdirSync, readFileSync } from 'fs';
import { readFile }                                  from 'fs/promises';
import { dirname, resolve }                          from 'path';

// ── Guard: CURSOR_API_KEY must be present before any SDK calls ────────────
const CURSOR_API_KEY = process.env.CURSOR_API_KEY;
if (!CURSOR_API_KEY) {
  process.stderr.write('CURSOR_API_KEY not set\n');
  process.stderr.write(
    '  Export before running: export CURSOR_API_KEY=<your-cursor-api-key>\n'
  );
  process.exit(1);
}

// ── Parse CLI arguments ───────────────────────────────────────────────────
const argv = process.argv.slice(2);  // strip 'node' and script path
if (argv.length < 6) {
  process.stderr.write(
    '[ERROR] Usage: run.mjs <driver> <stage> <work_dir> <prompt_file> <model> <log_file>\n'
  );
  process.exit(3);
}
const [driver, stage, workDir, promptFile, model, logFile] = argv;

// ── Resolve workspace root (workspace confinement) ────────────────────────
const projectRoot = process.env.PROJECT_ROOT || resolve(workDir);

// ── Read prompt file ───────────────────────────────────────────────────────
let stagePrompt;
try {
  stagePrompt = await readFile(promptFile, 'utf-8');
} catch {
  process.stderr.write(`[${stage}] Prompt file not found: ${promptFile}\n`);
  process.exit(3);
}

// ── Setup log file ────────────────────────────────────────────────────────
mkdirSync(dirname(resolve(logFile)), { recursive: true });
const logStream = createWriteStream(resolve(logFile), { flags: 'a' });

/** Write a line to the log file and stdout (streaming output). */
function writeToLog(content) {
  const line = typeof content === 'string' ? content : JSON.stringify(content);
  logStream.write(line + '\n');
  process.stdout.write(line + '\n');
}

// ── Rate-limit error classification (spec §8.14) ──────────────────────────
/**
 * Return true if the error signals a quota / rate-limit exhaustion.
 * Maps Cursor SDK rate-limit strings → exit code 2.
 */
function isRateLimitError(err) {
  const msg = String(err?.message ?? err?.code ?? err ?? '').toLowerCase();
  return (
    msg.includes('rate_limit') ||
    msg.includes('rate limit') ||
    msg.includes('quota') ||
    msg.includes('429') ||
    msg.includes('too_many_requests') ||
    msg.includes('too many requests') ||
    msg.includes('capacity') ||
    msg.includes('overloaded')
  );
}

// ── Dynamic import of @cursor/sdk ─────────────────────────────────────────
// Dynamic import keeps CURSOR_API_KEY check above and allows graceful
// error handling when the package is not yet installed.
let Agent;
try {
  const sdk = await import('@cursor/sdk');
  Agent = sdk.Agent;
} catch (importErr) {
  const msg = importErr?.message ?? String(importErr);
  process.stderr.write(
    `[${stage}] Cannot load @cursor/sdk: ${msg}\n`
  );
  process.stderr.write('  Install: cd drivers/cursor-sdk && npm install\n');
  logStream.end(() => process.exit(3));
  // Prevent further execution while the stream closes
  await new Promise(() => {});
}

// ── Main execution ────────────────────────────────────────────────────────
writeToLog(`[${stage}] sdk_cursor — model: ${model}, workspace: ${projectRoot}`);

let exitCode = 0;

try {
  // Create the Cursor agent — API key is passed but never logged
  const agent = await Agent.create({
    apiKey:  CURSOR_API_KEY,
    model:   { id: process.env.CURSOR_MODEL ?? model },
    local:   { cwd: projectRoot },   // workspace confinement per spec §8.2
  });

  writeToLog(`[${stage}] agent created, sending prompt`);

  const run = await agent.send(stagePrompt);

  // Stream events to log file
  for await (const event of run.stream) {
    writeToLog(event);
  }

  const result = await run.result;

  if (result.ok) {
    writeToLog(`[${stage}] completed successfully`);
    exitCode = 0;
  } else {
    writeToLog(
      `[${stage}] run returned failure: ${JSON.stringify(result.error ?? result)}`
    );
    exitCode = 1;
  }
} catch (err) {
  // Sanitize error — never expose the API key value
  const rawMsg  = String(err?.message ?? err ?? 'unknown error');
  const cleaned = rawMsg.replace(/sk-[A-Za-z0-9]{20,}/g, '[REDACTED]');

  writeToLog(`[${stage}] error: ${cleaned}`);
  process.stderr.write(`[${stage}] error: ${cleaned}\n`);

  if (isRateLimitError(err)) {
    process.stderr.write(
      `[${stage}] Rate-limit/quota detected — exit 2 for quota_retry\n`
    );
    exitCode = 2;
  } else {
    exitCode = 1;
  }
}

// ── Final scan: check log for rate-limit signals ──────────────────────────
// Some SDK versions emit rate-limit info in the event stream rather than
// throwing an error. Detect these patterns here.
logStream.end(() => {
  if (exitCode === 0) {
    try {
      const logContent = readFileSync(resolve(logFile), 'utf-8');
      if (
        /rate_limit|rate limit|quota_exceeded|429|too.many.requests/i.test(
          logContent
        )
      ) {
        process.stderr.write(
          `[${stage}] Rate-limit pattern found in log — exit 2 for quota_retry\n`
        );
        exitCode = 2;
      }
    } catch {
      // ignore scan errors
    }
  }
  process.exit(exitCode);
});
