const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = process.cwd();
const EMAILS_DB = path.join(PROJECT_ROOT, 'giipdb/emails.json');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'docs/51-features/ai-consultant/output');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Retrieve Gemini API Key
function getApiKey() {
    if (process.env.GEMINI_API_KEY) {
        return process.env.GEMINI_API_KEY;
    }
    const settingsPath = path.join(PROJECT_ROOT, '.agent/settings.json');
    if (fs.existsSync(settingsPath)) {
        try {
            const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
            if (settings.api_key && settings.api_key !== 'YOUR_GEMINI_API_KEY_HERE') {
                return settings.api_key;
            }
        } catch (e) {
            // Ignore parse errors
        }
    }
    return null;
}

// Action 1: Classify email and write draft response
async function processEmail(emailId, apiKey) {
    console.log(`\n⏳ 이메일 처리 중 (ID: ${emailId})...`);
    if (!fs.existsSync(EMAILS_DB)) {
        console.error('❌ 이메일 DB를 찾을 수 없습니다.');
        return;
    }

    let email = null;
    try {
        const emails = JSON.parse(fs.readFileSync(EMAILS_DB, 'utf8'));
        email = emails.find(e => e.id === emailId);
    } catch (e) {
        console.error('이메일 DB 파싱 에러:', e.message);
        return;
    }

    if (!email) {
        console.error('❌ 해당 ID의 이메일을 찾을 수 없습니다.');
        return;
    }

    if (!apiKey) {
        console.log('⚠️ GEMINI_API_KEY가 감지되지 않아 시뮬레이션(Dry-run) 모드로 실행합니다.');
        const result = simulateEmailProcessing(email);
        writeEmailReply(email, result);
        return;
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
    const prompt = `
아래 수신된 이메일을 분석하여 카테고리(예: Sales, Support, HR, Spam 등)로 분류하고, 
적절한 한글 답장 초안을 작성해서 JSON 형식으로 리턴해 주세요.
마크다운 \`\`\`json 기호 없이 순수 JSON만 리턴해 주세요.

{
  "category": "이메일 분류 카테고리",
  "replyDraft": "이메일 답장 내용 (발신자의 이름과 문의 사항을 정중하게 참조한 한글 본문)"
}

[이메일 정보]
보낸이: ${email.sender}
제목: ${email.subject}
본문: ${email.body}
`;

    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] })
        });

        if (!response.ok) throw new Error(`API error: ${response.status}`);
        const data = await response.json();
        let responseText = data.candidates[0].content.parts[0].text;
        responseText = responseText.replace(/```json/g, '').replace(/```/g, '').trim();
        const parsed = JSON.parse(responseText);

        writeEmailReply(email, parsed);
    } catch (err) {
        console.error('API 호출 중 오류로 시뮬레이션 모드로 이메일을 처리합니다:', err.message);
        const result = simulateEmailProcessing(email);
        writeEmailReply(email, result);
    }
}

function simulateEmailProcessing(email) {
    return {
        category: "Sales Inquiry",
        replyDraft: `안녕하세요, 고객님.
GIIP 테크의 대표 Lowy Shin입니다.

문의해주신 "${email.subject}"에 대하여 먼저 깊은 감사의 말씀을 올립니다.
요청하신 연동 솔루션 견적서 및 보안 사양 자료를 첨부파일로 함께 송부해 드립니다.

추가적인 기술 사양 조율이나 궁금하신 사항이 있으시면 언제든지 편하게 문의해 주시기 바랍니다.

감사합니다.
GIIP 테크 대표 Lowy Shin 드림.`
    };
}

function writeEmailReply(email, result) {
    const outputPath = path.join(OUTPUT_DIR, `reply_${email.id}.md`);
    const content = `# 수신 메일 및 AI 자동 답장 초안

## 1. 수신 메일 정보
- **보낸이**: ${email.sender}
- **제목**: ${email.subject}
- **분류 결과 (AI)**: ${result.category}

---

## 2. AI 추천 답장 초안 (Draft Reply)
\`\`\`text
${result.replyDraft}
\`\`\`
`;
    fs.writeFileSync(outputPath, content, 'utf8');
    
    // Update emails.json replied status
    try {
        const emails = JSON.parse(fs.readFileSync(EMAILS_DB, 'utf8'));
        const idx = emails.findIndex(e => e.id === email.id);
        if (idx !== -1) {
            emails[idx].replied = true;
            emails[idx].category = result.category;
            fs.writeFileSync(EMAILS_DB, JSON.stringify(emails, null, 2), 'utf8');
        }
    } catch (e) {
        // ignore update err
    }

    console.log(`✅ 이메일 분류 및 답장 초안 생성 완료: ${outputPath}`);
}

// Action 2: Analyze failed meeting minutes
async function analyzeFailedMeeting(transcriptPath, apiKey) {
    console.log(`\n⏳ 계약 불발 회의록 분석 중 (파일: ${transcriptPath})...`);
    let transcriptText = '';
    
    if (fs.existsSync(transcriptPath)) {
        transcriptText = fs.readFileSync(transcriptPath, 'utf8');
    } else {
        console.log('ℹ️ 입력 회의록 파일이 없어 기본 실패 케이스 회의록을 시뮬레이션 분석합니다.');
        transcriptText = `
김대표: 이번 글로벌테크와의 보안 API 솔루션 도입 건이 최종 무산되었습니다.
이지원: 원인이 무엇인가요?
김대표: 예산 범위가 400만 원 선이었으나 당사 견적 금액인 550만 원과 차이가 좁혀지지 않았습니다. 또한 데이터가 외부 클라우드로 유출되는 것에 대해 글로벌테크 보안팀의 반대가 극심했다고 합니다.
이지원: 온프레미스 망분리 패키지를 제안했어야 했는데 클라우드 전용만 고집했군요.
`;
    }

    if (!apiKey) {
        console.log('⚠️ GEMINI_API_KEY가 감지되지 않아 시뮬레이션(Dry-run) 모드로 분석 보고서를 생성합니다.');
        const mockReport = simulateMeetingAnalysis();
        writeReport(mockReport);
        return;
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
    const prompt = `
아래 계약 불발 회의록을 심층 분석하여, 불발 원인을 다각도로 분석하고 
다음 협상을 성공으로 이끌기 위한 컨설팅 및 대응 전략 보고서를 마크다운 형식으로 작성해 주세요.
반드시 보고서 파일에 들어갈 순수 마크다운 텍스트만 출력해 주세요.

[회의록]
${transcriptText}
`;

    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] })
        });

        if (!response.ok) throw new Error(`API error: ${response.status}`);
        const data = await response.json();
        const reportMarkdown = data.candidates[0].content.parts[0].text;
        writeReport(reportMarkdown);
    } catch (err) {
        console.error('API 분석 실패로 시뮬레이션 분석 보고서를 작성합니다:', err.message);
        writeReport(simulateMeetingAnalysis());
    }
}

function simulateMeetingAnalysis() {
    return `# 📉 계약 불발 심층 분석 및 대응 전략 보고서 (Deal Post-Mortem)

**분석 일자**: ${new Date().toISOString().split('T')[0]}
**담당 컨설턴트**: GIIP AI Strategy Consultant

---

## 1. 계약 불발의 핵심 요인 (Root Causes)

1. **가격 장벽 (Price Barrier)**:
   - 상대 측 예산 한도(400만 원)와 당사 제안가(550만 원) 간의 약 37% 예산 갭이 발생하여 이를 극복하지 못함.
2. **보안성 우려 (Cloud Security Concerns)**:
   - 데이터 외부 유출 위험성으로 인한 글로벌테크 보안 부서의 강한 반대와 통제 정책 충돌.

---

## 2. 향후 협상 전략 및 보완책 (Next Action Strategy)

- **유연한 가격 모델 제안**:
  - 일시불 구축 비용을 낮추는 대신 분기별 SaaS 라이선스 형태로 분할 제안하여 예산 장벽 완화 (예: 초기 300만 원 + 월 20만 원 유지보수).
- **온프레미스(On-Premise) / 폐쇄망 옵션 신설**:
  - 클라우드 전용 외에 고객사 인프라 내부에 직접 설치되는 설치형 패키지와 망분리 연동 모듈을 제안 라인업에 추가.
`;
}

function writeReport(content) {
    const reportPath = path.join(OUTPUT_DIR, 'failed_deal_report.md');
    fs.writeFileSync(reportPath, content, 'utf8');
    console.log(`✅ 계약 불발 원인 및 전략 제안서 발행 완료: ${reportPath}`);
}

async function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');

    const apiKey = getApiKey();

    if (isTest) {
        console.log('🧪 AI 전략 기획 및 컨설팅 모듈 테스트 실행 중...');
        await processEmail('MSG_202605220001', apiKey);
        await analyzeFailedMeeting('dummy_failed_meeting.txt', apiKey);
        return;
    }

    const emailIdx = args.indexOf('--classify-email');
    const meetingIdx = args.indexOf('--analyze-meeting');

    if (emailIdx !== -1 && args[emailIdx + 1]) {
        await processEmail(args[emailIdx + 1], apiKey);
    } else if (meetingIdx !== -1 && args[meetingIdx + 1]) {
        await analyzeFailedMeeting(args[meetingIdx + 1], apiKey);
    } else {
        console.error('사용법:');
        console.error('  이메일 처리: node ai_consultant.js --classify-email <이메일_ID>');
        console.error('  불발 분석: node ai_consultant.js --analyze-meeting <회의록_파일_경로>');
        console.error('  테스트 실행: node ai_consultant.js --test');
        process.exit(1);
    }
}

main();
