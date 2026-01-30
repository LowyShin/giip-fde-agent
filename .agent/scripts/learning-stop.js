#!/usr/bin/env node
/**
 * Claude Code Learning Stop Hook (v1.4.4)
 *
 * 학습 완료 후 다음 단계 제안
 *
 * @version 1.4.4
 * @module scripts/learning-stop
 */

let common = null;
function getCommon() {
  if (!common) {
    common = require('../lib/common.js');
  }
  return common;
}

function generateLearningCompletion(level) {
  const nextLevel = level < 5 ? level + 1 : null;

  return {
    completedLevel: level,
    nextLevel,
    suggestions: [
      nextLevel ? {
        action: `/claude-code-learning learn ${nextLevel}`,
        description: `Level ${nextLevel} 학습 계속`
      } : null,
      {
        action: '/claude-code-learning setup',
        description: '설정 자동 생성'
      },
      {
        action: '/pdca plan',
        description: 'PDCA 방법론으로 개발 시작'
      }
    ].filter(Boolean)
  };
}

function formatOutput(result, isGemini) {
  if (isGemini) {
    const lines = [
      '\n--- Claude Code Learning Complete ---\n',
      `✅ Level ${result.completedLevel} 학습 완료`,
      '',
      '💡 다음 단계 제안:',
      ...result.suggestions.map((s, i) => `   ${i + 1}. ${s.action} - ${s.description}`),
      ''
    ];
    return lines.join('\n');
  }
  return JSON.stringify({ status: 'success', ...result }, null, 2);
}

async function main() {
  const lib = getCommon();

  try {
    let input = '';
    if (process.stdin.isTTY === false) {
      const chunks = [];
      for await (const chunk of process.stdin) {
        chunks.push(chunk);
      }
      input = Buffer.concat(chunks).toString('utf8');
    }

    let level = 1;
    try {
      const context = JSON.parse(input);
      const args = context.tool_input?.args || '';
      const match = args.match(/\d+/);
      if (match) level = parseInt(match[0], 10);
    } catch (e) {}

    const result = generateLearningCompletion(level);
    const isGemini = lib.isGeminiCli();

    console.log(formatOutput(result, isGemini));
  } catch (e) {
    console.log(JSON.stringify({ status: 'error', error: e.message }));
  }
}

main().catch(e => {
  console.error('learning-stop.js error:', e.message);
  process.exit(1);
});
