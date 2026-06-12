const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = process.cwd();
const EMPLOYEES_DB = path.join(PROJECT_ROOT, 'docs', '51-features', '_data', 'employees.json');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'docs/51-features/admin-automation/output');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

function generateEmploymentCertificate(employee) {
    const certPath = path.join(OUTPUT_DIR, `cert_employment_${employee.name}.md`);
    const today = new Date().toISOString().split('T')[0];
    const todayKorean = today.split('-').map((v, i) => v + (i === 0 ? '년 ' : i === 1 ? '월 ' : '일')).join('');

    const content = `# 재 직 증 명 서 (Certificate of Employment)

| 인적사항 | 상세 내용 |
| :--- | :--- |
| **성 명** | ${employee.name} |
| **생년월일** | ${employee.birthDate} |
| **주 소** | ${employee.address} |

---

| 재직사항 | 상세 내용 |
| :--- | :--- |
| **소 속** | GIIP 테크 |
| **부 서** | ${employee.department} |
| **직 위** | ${employee.position} |
| **재직기간** | ${employee.joinDate} ~ 현재 |

---

**용 도**: 타사 재직 여부 확인 및 제출용

위와 같이 재직하고 있음을 증명합니다.

**발행일자**: ${todayKorean}

## GIIP 테크 대표 Lowy Shin (직인생략)
`;

    fs.writeFileSync(certPath, content, 'utf8');
    return certPath;
}

function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');

    let searchTarget = '';
    
    if (isTest) {
        console.log('🧪 사내 행정 자동화 모듈 테스트 실행 중...');
        searchTarget = '이지원';
    } else {
        searchTarget = args[0];
        if (!searchTarget) {
            console.error('사용법: node admin_cert_generator.js <사원_이름_또는_ID> [--test]');
            process.exit(1);
        }
    }

    console.log(`⏳ 사원 데이터 조회 중 (검색어: "${searchTarget}")...`);
    
    if (!fs.existsSync(EMPLOYEES_DB)) {
        console.error('❌ 사원 데이터베이스를 찾을 수 없습니다.');
        process.exit(1);
    }

    try {
        const employees = JSON.parse(fs.readFileSync(EMPLOYEES_DB, 'utf8'));
        const employee = employees.find(e => e.name === searchTarget || e.id === searchTarget);

        if (!employee) {
            console.error(`❌ 사원을 찾을 수 없습니다: ${searchTarget}`);
            process.exit(1);
        }

        console.log(`✅ 사원 확인 완료: ${employee.name} (${employee.department} / ${employee.position})`);
        
        console.log('⏳ 재직증명서(Certificate of Employment) 발급 중...');
        const certPath = generateEmploymentCertificate(employee);
        
        console.log(`🎉 발급 완료!`);
        console.log(`- 산출물 경로: docs/51-features/admin-automation/output/cert_employment_${employee.name}.md`);
    } catch (err) {
        console.error('증명서 발급 중 오류 발생:', err.message);
    }
}

main();
