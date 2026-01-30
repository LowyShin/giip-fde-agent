#!/usr/bin/env node
/**
 * Phase 9 Deployment Stop Hook (v1.4.4)
 *
 * Deployment 완료 후 최종 보고서 생성 제안
 * Phase 9 (Deployment) → PDCA Cycle 완료
 *
 * Pipeline의 마지막 단계로, 전체 개발 사이클 완료 처리
 *
 * @version 1.4.4
 * @module scripts/phase9-deploy-stop
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
    phase: 9,
    phaseName: 'Deployment',
    completedItems: [
      'CI/CD 파이프라인 구성',
      '환경별 설정 완료 (staging/production)',
      '배포 스크립트 작성',
      '모니터링 설정',
      '롤백 절차 문서화'
    ],
    pipelineComplete: true,
    summary: {
      totalPhases: 9,
      completedPhases: 9,
      status: 'SUCCESS'
    },
    nextActions: [
      { type: 'skill', name: 'pdca', args: 'report', description: 'PDCA 완료 보고서 생성' },
      { type: 'command', name: '/archive', description: '완료 문서 아카이브' },
      { type: 'skill', name: 'pdca', args: 'plan', description: '새로운 기능 개발 시작' }
    ],
    askUser: {
      question: '배포가 완료되었습니다! Development Pipeline 전체가 성공적으로 완료되었습니다.',
      options: [
        { label: 'PDCA 완료 보고서 생성', value: 'report' },
        { label: '문서 아카이브', value: 'archive' },
        { label: '새 기능 개발 시작', value: 'new-feature' },
        { label: '완료', value: 'done' }
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
      '\n========================================',
      '  Phase 9: Deployment 완료',
      '  Development Pipeline 성공!',
      '========================================\n',
      '✅ 완료 항목:',
      ...result.completedItems.map(item => `   - ${item}`),
      '',
      '📊 Pipeline 요약:',
      `   총 단계: ${result.summary.totalPhases}`,
      `   완료 단계: ${result.summary.completedPhases}`,
      `   상태: ${result.summary.status}`,
      '',
      '🎉 축하합니다! 전체 개발 사이클이 완료되었습니다.',
      '',
      '📝 다음 작업 선택:',
      ...result.nextActions.map((action, i) =>
        `   ${i + 1}. ${action.description}`
      ),
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
    lib.debugLog('Phase9Stop', 'Deployment phase completed - Pipeline finished');

    const result = generatePhaseCompletion();
    const isGemini = lib.isGeminiCli();

    console.log(formatOutput(result, isGemini));

    // Update pipeline status - mark as complete
    const memory = lib.readBkitMemory();
    if (memory) {
      if (!memory.pipelineStatus) {
        memory.pipelineStatus = {};
      }
      memory.pipelineStatus.currentPhase = null; // Pipeline complete
      memory.pipelineStatus.status = 'completed';
      memory.pipelineStatus.completedAt = new Date().toISOString();
      if (!memory.pipelineStatus.completedPhases) {
        memory.pipelineStatus.completedPhases = [];
      }
      // Ensure all phases marked complete
      for (let i = 1; i <= 9; i++) {
        if (!memory.pipelineStatus.completedPhases.includes(i)) {
          memory.pipelineStatus.completedPhases.push(i);
        }
      }
      memory.pipelineStatus.completedPhases.sort((a, b) => a - b);

      // Update PDCA status to 'act' phase
      if (memory.pdcaStatus) {
        memory.pdcaStatus.phase = 'act';
        memory.pdcaStatus.lastUpdated = new Date().toISOString();
      }

      lib.writeBkitMemory(memory);
    }

  } catch (e) {
    lib.debugLog('Phase9Stop', 'Error', { error: e.message });
    console.log(JSON.stringify({ status: 'error', error: e.message }));
  }
}

main().catch(e => {
  console.error('phase9-deploy-stop.js error:', e.message);
  process.exit(1);
});
