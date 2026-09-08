'use strict';

/**
 * Dependency-free token estimates for applying conservative prompt budgets.
 * The result is intentionally an estimate, not a tokenizer-specific count.
 */

function isCjkOrKana(codePoint) {
  return (
    (codePoint >= 0x1100 && codePoint <= 0x11ff) ||
    (codePoint >= 0x2e80 && codePoint <= 0x30ff) ||
    (codePoint >= 0x3130 && codePoint <= 0x318f) ||
    (codePoint >= 0x31f0 && codePoint <= 0x31ff) ||
    (codePoint >= 0x3400 && codePoint <= 0x9fff) ||
    (codePoint >= 0xa960 && codePoint <= 0xa97f) ||
    (codePoint >= 0xac00 && codePoint <= 0xd7ff) ||
    (codePoint >= 0xf900 && codePoint <= 0xfaff) ||
    (codePoint >= 0xff66 && codePoint <= 0xff9d) ||
    (codePoint >= 0x20000 && codePoint <= 0x323af)
  );
}

// Four units equal one estimated token.
function tokenUnits(text) {
  let units = 0;
  for (const character of String(text || '')) {
    const codePoint = character.codePointAt(0);
    if (codePoint <= 0x7f) units += 1;            // about 4 ASCII chars/token
    else if (isCjkOrKana(codePoint)) units += 4; // about 1 char/token
    else units += 2;                              // about 2 chars/token
  }
  return units;
}

function estimateTokens(text) {
  return Math.ceil(tokenUnits(text) / 4);
}

function takeWithinUnits(text, maxUnits) {
  let result = '';
  let used = 0;
  for (const character of String(text || '')) {
    const units = tokenUnits(character);
    if (used + units > maxUnits) break;
    result += character;
    used += units;
  }
  return { text: result, units: used };
}

function truncateToTokens(text, maxTokens, marker = '…') {
  const input = String(text || '');
  const budget = Number.isFinite(Number(maxTokens))
    ? Math.max(0, Math.floor(Number(maxTokens)))
    : 0;

  if (!input) return { text: '', truncated: false };
  if (budget <= 0) return { text: '', truncated: true };
  if (estimateTokens(input) <= budget) return { text: input, truncated: false };

  const maxUnits = budget * 4;
  const suffix = takeWithinUnits(marker, maxUnits);
  const prefix = takeWithinUnits(input, maxUnits - suffix.units);
  return { text: prefix.text + suffix.text, truncated: true };
}

module.exports = { estimateTokens, truncateToTokens };
