const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = process.cwd();
const EMAILS_DB = path.join(PROJECT_ROOT, 'docs', '51-features', '_data', 'emails.json');

// Mock Google Drive Upload
function syncFileToDrive(filePath) {
    console.log(`\n🔄 Google Drive API 파일 동기화 중...`);
    if (!fs.existsSync(filePath)) {
        console.error(`❌ 파일을 찾을 수 없습니다: ${filePath}`);
        return false;
    }
    const fileName = path.basename(filePath);
    const fileSize = fs.statSync(filePath).size;
    console.log(`- 업로드 대상 파일: ${fileName} (${fileSize} bytes)`);
    console.log(`✅ [Google Drive API Mock] 파일 업로드 완료 (File ID: GD_MOCK_${Date.now()})`);
    return true;
}

// Search consolidated emails
function searchEmails(query) {
    console.log(`\n🔍 통합 이메일 검색 (검색어: "${query}")...`);
    if (!fs.existsSync(EMAILS_DB)) {
        console.error('❌ 이메일 데이터베이스가 존재하지 않습니다.');
        return [];
    }
    
    try {
        const emails = JSON.parse(fs.readFileSync(EMAILS_DB, 'utf8'));
        const matches = emails.filter(email => 
            email.subject.toLowerCase().includes(query.toLowerCase()) ||
            email.body.toLowerCase().includes(query.toLowerCase()) ||
            email.sender.toLowerCase().includes(query.toLowerCase())
        );

        console.log(`📌 검색 완료: 총 ${matches.length}건이 발견되었습니다.\n`);
        matches.forEach((email, idx) => {
            console.log(`[${idx + 1}] 제목: ${email.subject}`);
            console.log(`    발신자: ${email.sender} | 수신일: ${email.date}`);
            console.log(`    본문 요약: ${email.body.substring(0, 80)}...`);
            console.log('----------------------------------------------------');
        });
        return matches;
    } catch (e) {
        console.error('이메일 검색 중 오류:', e.message);
        return [];
    }
}

// Sync mock incoming emails
function syncEmails() {
    console.log('🔄 IMAP/Gmail API 메일 동기화 중...');
    // We can simulate fetching emails and adding them to docs/51-features/_data/emails.json
    if (!fs.existsSync(EMAILS_DB)) {
        console.log('❌ DB가 없어 동기화가 불가합니다.');
        return;
    }

    try {
        const emails = JSON.parse(fs.readFileSync(EMAILS_DB, 'utf8'));
        const newEmail = {
            id: `MSG_${Date.now()}`,
            sender: "partner@globaltech.com",
            recipient: "office@giip.net",
            subject: "글로벌 테크 협력 제안서 보강 자료",
            body: "지난번 전달해주신 내용 검토했으며, 당사 보완 자료 송부합니다. 확인 부탁드립니다.",
            date: new Date().toISOString(),
            category: "Business Collaboration",
            replied: false
        };

        const duplicate = emails.some(e => e.subject === newEmail.subject);
        if (!duplicate) {
            emails.push(newEmail);
            fs.writeFileSync(EMAILS_DB, JSON.stringify(emails, null, 2), 'utf8');
            console.log(`✅ 신규 이메일 1건 동기화 완료: "${newEmail.subject}"`);
        } else {
            console.log('ℹ️ 동기화할 새로운 이메일이 없습니다.');
        }
    } catch (err) {
        console.error('이메일 동기화 중 오류:', err.message);
    }
}

function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');
    const searchIdx = args.indexOf('--search');
    const uploadIdx = args.indexOf('--upload');

    if (isTest) {
        console.log('🧪 파일 및 이메일 통합 모듈 테스트 실행 중...');
        syncEmails();
        searchEmails('견적');
        // create temporary file to test drive upload
        const tempFilePath = path.join(PROJECT_ROOT, 'temp_drive_test.txt');
        fs.writeFileSync(tempFilePath, 'This is a temporary file for drive upload testing.', 'utf8');
        syncFileToDrive(tempFilePath);
        fs.unlinkSync(tempFilePath); // Cleanup
        return;
    }

    if (searchIdx !== -1 && args[searchIdx + 1]) {
        searchEmails(args[searchIdx + 1]);
    } else if (uploadIdx !== -1 && args[uploadIdx + 1]) {
        syncFileToDrive(args[uploadIdx + 1]);
    } else if (args.includes('--sync-emails')) {
        syncEmails();
    } else {
        console.error('사용법:');
        console.error('  이메일 검색: node file_email_sync.js --search <검색어>');
        console.error('  이메일 동기화: node file_email_sync.js --sync-emails');
        console.error('  드라이브 업로드: node file_email_sync.js --upload <파일_경로>');
        console.error('  테스트 실행: node file_email_sync.js --test');
        process.exit(1);
    }
}

main();
