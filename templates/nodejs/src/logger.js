'use strict';

/**
 * Structured JSON logger for myapp.
 * All output is to stderr to keep stdout clean for data pipelines.
 * Use this instead of console.log throughout the codebase.
 *
 * @module src/logger
 */

const LEVELS = Object.freeze({ debug: 0, info: 1, warn: 2, error: 3 });

const _minLevel = LEVELS[process.env.LOG_LEVEL ?? 'info'] ?? LEVELS.info;

function _emit(level, message, extra) {
  if (LEVELS[level] < _minLevel) return;
  const entry = {
    ts: new Date().toISOString(),
    level,
    msg: message,
    ...extra,
  };
  process.stderr.write(JSON.stringify(entry) + '\n');
}

const logger = Object.freeze({
  /** @param {string} msg @param {object} [extra] */
  debug: (msg, extra = {}) => _emit('debug', msg, extra),
  /** @param {string} msg @param {object} [extra] */
  info: (msg, extra = {}) => _emit('info', msg, extra),
  /** @param {string} msg @param {object} [extra] */
  warn: (msg, extra = {}) => _emit('warn', msg, extra),
  /** @param {string} msg @param {object} [extra] */
  error: (msg, extra = {}) => _emit('error', msg, extra),
});

module.exports = { logger };
