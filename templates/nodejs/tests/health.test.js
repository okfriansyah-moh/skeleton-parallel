'use strict';

/**
 * Unit tests for the health module.
 *
 * Tests are deterministic, network-free, and require no external services.
 * Follow AAA pattern: Arrange → Act → Assert.
 *
 * @module tests/health.test
 */

const { checkHealth } = require('../src/modules/health/feature/check');

describe('checkHealth', () => {
  it('returns status ok', () => {
    // Arrange — no setup needed (pure function)

    // Act
    const result = checkHealth();

    // Assert
    expect(result.status).toBe('ok');
  });

  it('returns a checked_at ISO timestamp', () => {
    const result = checkHealth();
    expect(() => new Date(result.checked_at)).not.toThrow();
    expect(new Date(result.checked_at).toISOString()).toBe(result.checked_at);
  });

  it('returns a frozen (immutable) object', () => {
    const result = checkHealth();
    expect(Object.isFrozen(result)).toBe(true);
  });

  it('does not mutate the result', () => {
    const result = checkHealth();
    expect(() => {
      result.status = 'error';
    }).toThrow();
  });
});
