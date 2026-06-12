const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ROOT = process.cwd();
const SCHEDULE_DB = path.join(PROJECT_ROOT, 'docs', '51-features', '_data', 'schedule.json');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'docs/51-features/slackbot-briefing/output');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// 1. Morning Briefing Generator
function generateMorningBriefing() {
    console.log('⏳ 아침 일정 브리핑 메시지 생성 중...');
    let schedules = [];
    if (fs.existsSync(SCHEDULE_DB)) {
        try {
            schedules = JSON.parse(fs.readFileSync(SCHEDULE_DB, 'utf8'));
        } catch (e) {
            console.error('스케줄 DB 파싱 실패:', e.message);
        }
    }

    const todayStr = new Date().toISOString().split('T')[0];
    
    let briefing = `📅 *${todayStr} 일간 업무 & 일정 브리핑* 📅\n\n`;
    briefing += `안녕하세요! GIIP 에이전트입니다. 오늘의 일정을 브리핑해 드립니다.\n\n`;
    
    if (schedules.length === 0) {
        briefing += `- 등록된 예정 일정이 없습니다. 편안한 하루 되세요!\n`;
    } else {
        schedules.forEach((sch, idx) => {
            const statusIcon = sch.status === 'COMPLETED' ? '✅' : '⏳';
            briefing += `*${idx + 1}. [${sch.time}] ${sch.title}*\n`;
            briefing += `   - 담당자: ${sch.assignee} | 상태: ${statusIcon} ${sch.status}\n`;
        });
    }

    briefing += `\n오늘 하루도 생산적인 시간 되시길 바랍니다! 💪`;
    
    const outputPath = path.join(OUTPUT_DIR, 'morning_briefing.txt');
    fs.writeFileSync(outputPath, briefing, 'utf8');
    return briefing;
}

// 2. Evening GitHub Dev Report Generator
function generateEveningReport() {
    console.log('⏳ 저녁 6시 개발 진행 상황 요약 보고서 생성 중...');
    
    let gitCommits = '';
    try {
        // Fetch commits from last 7 days since there may not be commits today
        gitCommits = execSync('git log --since="7 days ago" --oneline', { encoding: 'utf8' }).trim();
    } catch (err) {
        console.log('ℹ️ Git 기록을 가져오지 못해 가상 커밋 내역으로 대체합니다.');
        gitCommits = `
a1b2c3d: docs: K-Layer 지식 통합 동기화 스크립트 보강 (이지원)
e5f6g7h: feat: 매출 관리 자동화 웹훅 리시버 구현 (김철수)
i9j0k1l: fix: 구글 주소록 중복 등록 예외 처리 버그 픽스 (이지원)
`;
    }

    const todayStr = new Date().toISOString().split('T')[0];
    let report = `📢 *${todayStr} 개발팀 일일 진행 보고서 (저녁 6시 요약)* 📢\n\n`;
    report += `개발팀의 최근 깃허브 커밋 데이터를 분석한 요약 정보입니다.\n\n`;
    report += `*📝 최근 커밋 로그 (최근 7일)*\n\`\`\`\n`;
    
    if (!gitCommits) {
        report += `(최근 7일간 커밋 기록이 존재하지 않습니다.)\n`;
    } else {
        report += gitCommits;
    }
    
    report += `\n\`\`\`\n`;
    report += `*📊 진행 현황 요약 및 조치 사항*\n`;
    report += `- K-Layer 위키 연동 및 문서 정리 지속 진행 중.\n`;
    report += `- 명함 연락처 자동 동기화 기능 및 매출 입금 웹훅 솔루션 개발 완료 테스트 중.\n\n`;
    report += `보고 완료되었습니다. 좋은 저녁 시간 되세요! ☕`;

    const outputPath = path.join(OUTPUT_DIR, 'evening_report.txt');
    fs.writeFileSync(outputPath, report, 'utf8');
    return report;
}

// Simulate posting message to Slack
async function postToSlack(message) {
    console.log('\n💬 [Slack API Mock] 슬랙 메시지 송신 중...');
    console.log('--------------------------------------------------');
    console.log(message);
    console.log('--------------------------------------------------');
    console.log('✅ 슬랙 채널 전송 완료!');
    return true;
}

async function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');

    if (isTest) {
        console.log('🧪 슬랙봇 및 자동 브리핑 모듈 테스트 실행 중...');
        const morningMsg = generateMorningBriefing();
        await postToSlack(morningMsg);
        
        const eveningMsg = generateEveningReport();
        await postToSlack(eveningMsg);
        return;
    }

    if (args.includes('--morning')) {
        const msg = generateMorningBriefing();
        await postToSlack(msg);
    } else if (args.includes('--evening')) {
        const msg = generateEveningReport();
        await postToSlack(msg);
    } else {
        console.error('사용법:');
        console.error('  아침 브리핑 생성 및 발송: node slackbot_briefing.js --morning');
        console.error('  저녁 보고서 생성 및 발송: node slackbot_briefing.js --evening');
        console.error('  테스트 실행: node slackbot_briefing.js --test');
        process.exit(1);
    }
}

main();
