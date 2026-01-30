#!/usr/bin/env node
/**
 * Phase 5 Design System Stop Hook (v1.4.4)
 *
 * Design System 구축 완료 후 다음 단계 제안
 * Phase 5 (Design System) → Phase 6 (UI Integration)
 *
 * @version 1.4.4
 * @module scripts/phase5-design-stop
 */

const path = require('path');

let common = null;
function getCommon() {
  if (!common) {
    common = require('../lib/common.js');
  }
  return common;
}

/**
 * Generate phase completion message
 * @returns {Object} Hook result
 */
function generatePhaseCompletion() {
  return {
    phase: 5,
    phaseName: 'Design System',
    completedItems: [
      'UI 컴포넌트 라이브러리 구축',
      '디자인 토큰 정의 (colors, spacing, typography)',
      '컴포넌트 문서화',
      'Storybook 설정 (선택)'
    ],
    nextPhase: {
      number: 6,
      name: 'UI Integration',
      skill: 'phase-6-ui-integration',
      description: 'UI 구현 및 API 연동'
    },
    askUser: {
      question: 'Design System 구축이 완료되었습니다. UI Integration 단계로 진행하시겠습니까?',
      options: [
        { label: '예, Phase 6 진행', value: 'proceed' },
        { label: '추가 컴포넌트 작업', value: 'continue' },
        { label: '리뷰 후 진행', value: 'review' }
      ]
    }
  };
}

/**
 * Format output for different CLI environments
 * @param {Object} result - Hook result
 * @param {boolean} isGemini - Is Gemini CLI
 * @returns {string} Formatted output
 */
function formatOutput(result, isGemini) {
  if (isGemini) {
    const lines = [
      '\n--- Phase 5: Design System 완료 ---\n',
      '✅ 완료 항목:',
      ...result.completedItems.map(item => `   - ${item}`),
      '',
      `📍 다음 단계: Phase ${result.nextPhase.number} - ${result.nextPhase.name}`,
      `   ${result.nextPhase.description}`,
      '',
      `💡 진행하려면: /${result.nextPhase.skill}`,
      ''
    ];
    return lines.join('\n');
  }

  return JSON.stringify({
    status: 'success',
    ...result
  }, null, 2);
}

/**
 * Main execution
 */
async function main() {
  const lib = getCommon();

  try {
    lib.debugLog('Phase5Stop', 'Design System phase completed');

    const result = generatePhaseCompletion();
    const isGemini = lib.isGeminiCli();

    console.log(formatOutput(result, isGemini));

    // Update pipeline status
    const memory = lib.readBkitMemory();
    if (memory) {
      if (!memory.pipelineStatus) {
        memory.pipelineStatus = {};
      }
      memory.pipelineStatus.currentPhase = 6;
      if (!memory.pipelineStatus.completedPhases) {
        memory.pipelineStatus.completedPhases = [];
      }
      if (!memory.pipelineStatus.completedPhases.includes(5)) {
        memory.pipelineStatus.completedPhases.push(5);
      }
      lib.writeBkitMemory(memory);
    }

  } catch (e) {
    lib.debugLog('Phase5Stop', 'Error', { error: e.message });
    console.log(JSON.stringify({ status: 'error', error: e.message }));
  }
}

main().catch(e => {
  console.error('phase5-design-stop.js error:', e.message);
  process.exit(1);
});
