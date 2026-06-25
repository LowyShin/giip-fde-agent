const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = process.cwd();
const SALES_DB = path.join(PROJECT_ROOT, 'docs', '51-features', '_data', 'sales.json');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'docs/51-features/sales-invoicing/output');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Generate Invoice / Receipt document
function generateInvoiceDocument(transaction) {
    const docPath = path.join(OUTPUT_DIR, `invoice_${transaction.id}.md`);
    const dateStr = transaction.date.split('T')[0];
    
    const invoiceContent = `# 청구서 및 입금 확인서 (Invoice & Receipt)

**문서 번호**: INV-${transaction.id}
**발행 일자**: ${dateStr}

---

## 1. 거래 내역 (Transaction Details)
- **거래 ID**: ${transaction.id}
- **입금자 / 상호**: ${transaction.sender}
- **결제 금액**: ${transaction.amount.toLocaleString()} 원
- **결제 수단**: ${transaction.paymentMethod}
- **처리 상태**: ${transaction.status}

---

## 2. 공급자 정보
- **상호명**: GIIP 테크
- **대표자**: Lowy Shin
- **사업자 등록번호**: 123-45-67890
- **소재지**: 서울시 마포구 백범로 31

---

## 3. 영수 내역
위 금액을 영수(또는 청구)함.

**GIIP 테크 대표 Lowy Shin** (인)
`;
    
    fs.writeFileSync(docPath, invoiceContent, 'utf8');
    return docPath;
}

// Mock Tax Invoice Issuance (Popbill, Barobill etc.)
function issueTaxInvoice(transaction) {
    console.log(`\n🔄 국세청 홈택스 연동 세금계산서 발행 시뮬레이션...`);
    console.log(`- 공급받는자: ${transaction.sender}`);
    console.log(`- 가액: ${Math.round(transaction.amount / 1.1).toLocaleString()} 원`);
    console.log(`- 부가세: ${Math.round(transaction.amount - (transaction.amount / 1.1)).toLocaleString()} 원`);
    console.log(`✅ [Popbill API Mock] 전자세금계산서 임시 저장 및 발행 요청 완료 (임시승인번호: TAX-${transaction.id})`);
    return true;
}

function main() {
    const args = process.argv.slice(2);
    const isTest = args.includes('--test');

    let payload = null;

    if (isTest) {
        console.log('🧪 매출 및 청구서 자동 발행 모듈 테스트 실행 중...');
        // Simulating Toss Payments webhook notification payload
        payload = {
            id: `TX_${Date.now()}`,
            amount: 770000,
            sender: "한결코퍼레이션",
            paymentMethod: "Virtual Account (국민은행)",
            status: "COMPLETED",
            date: new Date().toISOString()
        };
    } else {
        // Expect JSON payload as argument
        const rawJson = args[0];
        if (!rawJson) {
            console.error('사용법: node sales_tracker.js \'<JSON_PAYLOAD>\' [--test]');
            console.error('예: node sales_tracker.js \'{"id":"TX_999","amount":150000,"sender":"홍길동","paymentMethod":"Card","status":"COMPLETED","date":"2026-05-23T10:00:00Z"}\'');
            process.exit(1);
        }
        try {
            payload = JSON.parse(rawJson);
        } catch (e) {
            console.error('올바르지 않은 JSON 형식입니다:', e.message);
            process.exit(1);
        }
    }

    console.log('⏳ 결제 내역 확인 및 데이터 가공 중...');
    
    // Save to sales DB
    if (fs.existsSync(SALES_DB)) {
        try {
            const sales = JSON.parse(fs.readFileSync(SALES_DB, 'utf8'));
            
            // Check for duplicates
            const exists = sales.some(s => s.id === payload.id);
            if (!exists) {
                sales.push(payload);
                fs.writeFileSync(SALES_DB, JSON.stringify(sales, null, 2), 'utf8');
                console.log(`✅ 사내 매출 DB(docs/51-features/_data/sales.json)에 신규 매출이 연동되었습니다. (${payload.amount}원, 입금자: ${payload.sender})`);
            } else {
                console.log('ℹ️ 이미 등록된 거래 건입니다. DB 갱신을 생략합니다.');
            }
        } catch (e) {
            console.error('매출 DB 기록 중 오류:', e.message);
        }
    }

    // Generate Invoice Document
    const docPath = generateInvoiceDocument(payload);
    console.log(`✅ 청구서/확인서 문서가 발행되었습니다: ${docPath}`);

    // If transaction status is COMPLETED, request tax invoice issuance
    if (payload.status === 'COMPLETED') {
        issueTaxInvoice(payload);
        
        // Update DB with tax invoice flag
        try {
            const sales = JSON.parse(fs.readFileSync(SALES_DB, 'utf8'));
            const txIdx = sales.findIndex(s => s.id === payload.id);
            if (txIdx !== -1) {
                sales[txIdx].taxInvoiceIssued = true;
                fs.writeFileSync(SALES_DB, JSON.stringify(sales, null, 2), 'utf8');
                console.log('✅ 매출 내역의 세금계산서 발행 여부가 업데이트되었습니다.');
            }
        } catch (err) {
            console.error('DB 세금계산서 상태 갱신 실패:', err.message);
        }
    }
}

main();
