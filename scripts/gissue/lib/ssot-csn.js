#!/usr/bin/env node
/**
 * CSN 단일 진실 소스(SSOT) 파서 — giip #3405.
 *
 * 이 docker 배포 모델은 "컨테이너 1개 = 프로젝트(CSN) 1개"다. 그래서 이 머신이 처리하는 CSN 은
 * scripts/gissue/csn-projects.json 의 단일 최상위 `csn` 키가 정본(SSOT)이다. GIIP_CSN 환경변수는
 * 최초 기동 때 이 파일을 생성하는 입력일 뿐, 컨테이너 프로세스에 박혀 클론+CSN 교체 후 stale 된다
 * (giip #3405 caci-skp 인시던트: cron=47 인데 매핑=70434 로 조용히 어긋남).
 *
 * entrypoint.sh 와 check-csn-consistency.sh 가 공용으로 이 파서를 써서 "이 머신의 CSN" 을 한 곳
 * (csn-projects.json)에서만 읽는다.
 *
 * 사용: node ssot-csn.js <path-to-csn-projects.json>
 * stdout: 유효하면 단일 csn 키(숫자 문자열) 1줄.
 * 종료코드:
 *   0 = csn 키가 정확히 1개(그 값을 stdout 에 출력)
 *   1 = 파일 없음 / JSON 파싱 실패 / csn 블록 없음 / csn 키가 0개 (stderr 에 사유)
 *   2 = csn 키가 2개 이상(docker 모델 위반 — stderr 에 키 목록)
 */
const fs = require('fs');

const mapPath = process.argv[2];
if (!mapPath) {
  console.error('사용법: node ssot-csn.js <path-to-csn-projects.json>');
  process.exit(1);
}
if (!fs.existsSync(mapPath)) {
  console.error(`[ssot-csn] 파일 없음: ${mapPath}`);
  process.exit(1);
}

let doc;
try {
  const raw = fs.readFileSync(mapPath, 'utf8');
  const bom = raw.charCodeAt(0) === 0xfeff;
  doc = JSON.parse(bom ? raw.slice(1) : raw);
} catch (e) {
  console.error(`[ssot-csn] JSON 파싱 실패: ${e.message}`);
  process.exit(1);
}

const keys = doc && doc.csn ? Object.keys(doc.csn) : [];
if (keys.length === 0) {
  console.error('[ssot-csn] csn 블록에 항목이 없습니다.');
  process.exit(1);
}
if (keys.length > 1) {
  console.error(`[ssot-csn] csn 키가 ${keys.length}개입니다(docker 모델은 컨테이너당 1개): ${keys.join(', ')}`);
  process.exit(2);
}
process.stdout.write(String(keys[0]) + '\n');
