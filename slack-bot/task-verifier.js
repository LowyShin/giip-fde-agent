/**
 * 작업 완료 여부를 명시적인 실행 결과만으로 판정한다.
 * 파일 조회나 프로세스 실행은 호출자가 담당하며, 이 모듈은 부작용이 없다.
 */

const PASS_STATUSES = new Set(['pass', 'passed', 'success', 'succeeded', 'ok']);
const FAIL_STATUSES = new Set(['fail', 'failed', 'error', 'errored']);

function latestResultsByCommand(testResults) {
  const latest = new Map();
  (Array.isArray(testResults) ? testResults : []).forEach((result, index) => {
    const item = result && typeof result === 'object' ? result : {};
    const command = String(item.command || '').trim();
    const key = command || `__missing_command_${index}`;
    latest.set(key, Object.assign({}, item, {
      command: command || null,
      status: String(item.status || '').trim().toLowerCase(),
    }));
  });
  return Array.from(latest.values());
}

function verdict(ok, code, reason, details) {
  return { ok, code, reason, details };
}

function verifyCompletion(input = {}) {
  const sourceFiles = Array.isArray(input.sourceFiles) ? input.sourceFiles : [];
  const reportedCount = Number.isFinite(Number(input.totalSourceChanges))
    ? Math.max(0, Number(input.totalSourceChanges))
    : 0;
  const sourceChangeCount = Math.max(sourceFiles.length, reportedCount);
  const blocked = Array.isArray(input.blocked) ? input.blocked : [];
  const latestTestResults = latestResultsByCommand(input.testResults);
  const details = {
    sourceChangeCount,
    blockedCount: blocked.length,
    latestTestResults,
  };

  if (input.resultFileExists !== true) {
    return verdict(false, 'missing_result_file', '결과 파일이 없습니다.', details);
  }
  if (blocked.length > 0) {
    return verdict(false, 'unresolved_blocked', '해소되지 않은 차단 항목이 있습니다.', details);
  }

  const failed = latestTestResults.find(result => FAIL_STATUSES.has(result.status));
  if (failed) {
    return verdict(false, 'latest_test_failed', '최신 테스트 결과에 실패가 있습니다.', details);
  }

  const unknown = latestTestResults.find(result => !PASS_STATUSES.has(result.status));
  if (unknown) {
    return verdict(false, 'unknown_test_status', '인식할 수 없는 최신 테스트 상태가 있습니다.', details);
  }

  const hasPassingTest = latestTestResults.some(result => PASS_STATUSES.has(result.status));
  if (sourceChangeCount > 0 && !hasPassingTest) {
    return verdict(false, 'missing_passing_test', '소스 변경에는 최신 통과 테스트가 필요합니다.', details);
  }

  return verdict(true, 'verified', '완료 조건을 충족했습니다.', details);
}

module.exports = {
  PASS_STATUSES,
  FAIL_STATUSES,
  latestResultsByCommand,
  verifyCompletion,
};
