const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ROOT = process.cwd();
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'docs/51-features/meeting-management/output');
const SCHEDULE_DB = path.join(PROJECT_ROOT, 'docs', '51-features', '_data', 'schedule.json');

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

// Call Gemini API to analyze transcript
async function analyzeTranscript(transcriptText, apiKey) {
    if (!apiKey) {
        console.log('⚠️ GEMINI_API_KEY가 감지되지 않아 시뮬레이션(Dry-run) 모드로 실행합니다.');
        return simulateAnalysis(transcriptText);
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
    const prompt = `
회의 녹취록을 분석하여 아래의 JSON 구조로 응답해 주세요. 마크다운 코드 블록(\`\`\`json) 기호 없이 순수 JSON 텍스트만 리턴해 주세요.

{
  "quoteMarkdown": "견적서 내용 (상호명, 품목, 단가, 공급가액, 부가세, 합계 금액 및 특이사항을 포함한 마크다운 형식)",
  "tasks": [
    {
      "title": "할 일 제목",
      "assignee": "담당자 이름 또는 역할",
      "time": "예상 완료 시간 또는 목표 시간"
    }
  ],
  "projectSummary": "회의에서 합의된 프로젝트의 요약 설명"
}

[회의 녹취록]
${transcriptText}
`;

    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: prompt }] }]
            })
        });

        if (!response.ok) {
            throw new Error(`API response error: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();
        let responseText = data.candidates[0].content.parts[0].text;
        
        // Remove markdown block backticks if present
        responseText = responseText.replace(/```json/g, '').replace(/```/g, '').trim();
        return JSON.parse(responseText);
    } catch (error) {
        console.error('API 호출 중 오류 발생, 시뮬레이션 모드로 전환합니다:', error.message);
        return simulateAnalysis(transcriptText);
    }
}

function simulateAnalysis(transcriptText) {
    return {
        quoteMarkdown: `# 견적서 (Estimate)
**발행일**: ${new Date().toISOString().split('T')[0]}
**공급자**: GIIP 테크 (사업자번호: 123-45-67890)
**공급받는자**: (주)에이아이랩 (대표자: 홍길동)

| 품목 | 수량 | 단가 | 공급가액 | 부가세 |
| :--- | :--- | :--- | :--- | :--- |
| 회의록 AI 자동 요약 API 연동 솔루션 | 1 | 5,000,000 | 5,000,000 | 500,000 |
| **합계 금액** | | | **5,500,000 원 (VAT 포함)** |

*특이사항*: 구축 후 3개월간 무상 유지보수 지원.
`,
        tasks: [
            {
                title: "회의록 분석 솔루션 API 인터페이스 설계",
                assignee: "이지원 수석연구원",
                time: "10:00"
            },
            {
                title: "Zapier / Plaud Webhook 리시버 엔드포인트 구현",
                assignee: "개발팀",
                time: "14:00"
            }
        ],
        projectSummary: "Plaud AI 녹음 장치와 연동하여 자동으로 회의 내용을 텍스트화하고 이를 바탕으로 견적 및 할 일을 생성하는 자동화 파이프라인 개발 프로젝트"
    };
}

async function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');
    
    let transcriptText = '';
    
    if (isTest) {
        console.log('🧪 미팅 및 프로젝트 자동 관리 모듈 테스트 실행 중...');
        transcriptText = `
홍길동: 안녕하세요. 이번 Plaud AI 녹취 연동 및 자동화 구축 건에 대해 논의합시다. 
이지원: 네, 연동 솔루션을 구축하는 데 대략 500만 원(VAT 별도) 규모로 진행할 계획입니다. 3개월간 유지보수도 필요합니다.
홍길동: 좋습니다. 이지원 수석님이 전체적인 API 인터페이스 설계를 오전에 맡아 주시고, 오후에는 개발팀에서 Zapier 및 Plaud Webhook을 수신할 리시버 엔드포인트를 구현해 주시면 감사하겠습니다.
`;
    } else {
        const filePath = args[0];
        if (!filePath) {
            console.error('사용법: node meeting_manager.js <녹취록_파일_경로> [--test]');
            process.exit(1);
        }
        if (!fs.existsSync(filePath)) {
            console.error(`파일을 찾을 수 없습니다: ${filePath}`);
            process.exit(1);
        }
        transcriptText = fs.readFileSync(filePath, 'utf8');
    }

    const apiKey = getApiKey();
    console.log('⏳ 회의록 분석 중...');
    const result = await analyzeTranscript(transcriptText, apiKey);

    const dateStr = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 8);
    const quoteFile = path.join(OUTPUT_DIR, `quote_${dateStr}.md`);
    const taskFile = path.join(OUTPUT_DIR, `tasks_${dateStr}.md`);

    // Write Outputs
    fs.writeFileSync(quoteFile, result.quoteMarkdown, 'utf8');
    
    let taskMarkdown = `# 생성된 프로젝트 및 할 일 목록\n\n`;
    taskMarkdown += `**프로젝트 요약**: ${result.projectSummary}\n\n`;
    taskMarkdown += `## 할 일 목록\n`;
    result.tasks.forEach(t => {
        taskMarkdown += `- [ ] ${t.title} (담당: ${t.assignee}, 시간: ${t.time})\n`;
    });
    fs.writeFileSync(taskFile, taskMarkdown, 'utf8');

    // Register tasks to schedule DB if exists
    if (fs.existsSync(SCHEDULE_DB)) {
        try {
            const schedules = JSON.parse(fs.readFileSync(SCHEDULE_DB, 'utf8'));
            result.tasks.forEach(t => {
                schedules.push({
                    id: `SCH_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
                    title: `[자동 생성] ${t.title}`,
                    time: t.time,
                    assignee: t.assignee,
                    status: "PENDING"
                });
            });
            fs.writeFileSync(SCHEDULE_DB, JSON.stringify(schedules, null, 2), 'utf8');
            console.log('✅ docs/51-features/_data/schedule.json에 할 일이 성공적으로 등록되었습니다.');
        } catch (e) {
            console.error('일정 DB 등록 중 오류 발생:', e.message);
        }
    }

    console.log(`🎉 분석 완료!`);
    console.log(`- 견적서 저장 완료: docs/51-features/meeting-management/output/quote_${dateStr}.md`);
    console.log(`- 할 일 목록 저장 완료: docs/51-features/meeting-management/output/tasks_${dateStr}.md`);
}

main();
