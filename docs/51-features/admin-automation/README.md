# 사내 행정 자동화 모듈 (Internal Administration Automation) 📄

이 모듈은 사내 인사 정보 데이터베이스(`giipdb/employees.json`)와 연동하여, 재직증명서(Certificate of Employment) 등의 행정 서류를 시스템에서 원클릭으로 자동 발급하고 보관할 수 있게 돕습니다.

---

## 🛠️ 주요 기능

1. **인사 DB 연동 조회**: 사원 번호 또는 성명을 입력받아 유효한 재직 정보를 실시간으로 파싱합니다.
2. **표준 재직증명서 자동 문서화**: 국문/영문 혼용 표준 레이아웃에 맞춰 마크다운 기반 증명서를 즉각 생성하고 `output/` 폴더에 분류하여 백업합니다.

---

## 🚀 사용법

### 1. 테스트 실행 (기본 사원 '이지원' 대상 발급 테스트)
```powershell
node docs/51-features/admin-automation/admin_cert_generator.js --test
```

### 2. 특정 사원의 재직증명서 발급 실행
```powershell
node docs/51-features/admin-automation/admin_cert_generator.js <사원명_또는_사원번호>
```

---

## ⚙️ PDF 또는 인쇄물 연동 가이드

마크다운 형식으로 생성된 문서를 실제 공식 문서 포맷(PDF)으로 가공하여 직원에게 메일로 자동 발급하려면 다음과 같은 연동을 수행할 수 있습니다.

### A. Pandoc / HTML-PDF 변환 엔진 연동
터미널에서 `pandoc` 또는 `headless chrome`을 사용해 PDF로 자동 변환합니다.
```powershell
# Node.js 스크립트에 HTML 변환 및 PDF 모듈 연동 예시 (puppeteer 사용)
const puppeteer = require('puppeteer');
const marked = require('marked');

async function convertToPdf(mdPath, pdfPath) {
    const mdContent = fs.readFileSync(mdPath, 'utf8');
    const htmlContent = marked.parse(mdContent);
    
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.setContent(htmlContent);
    await page.pdf({ path: pdfPath, format: 'A4' });
    await browser.close();
}
```

### B. Slack / Email 발송 연동
발행 완료 이벤트를 수집하여 사원 정보 이메일 주소로 PDF 파일을 첨부하여 메일 자동 발송 또는 사내 슬랙의 사원 개인 DM으로 서류를 즉각 전송합니다.
