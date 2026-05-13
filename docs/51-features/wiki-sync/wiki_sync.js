const fs = require('fs');
const path = require('path');

// Configuration - Use current working directory for portability
const PROJECT_ROOT = process.cwd();
const KNOWLEDGE_DIR = path.join(PROJECT_ROOT, '.agent/knowledge/notes');
const WIKI_DIR = path.join(PROJECT_ROOT, 'wiki');

// Mapping: Keyword to Wiki Page (Relative to WIKI_DIR)
const MAPPING = {
    "entities/giip.md": ["GIIP", "Azure", "API", "Function"],
    "concepts/n-slash-a-b-i.md": ["Bkit", "PDCA", "NABI", "Protocol", "Rule", "Standard", "Convention", "native-trace", "aioptimize", "startagent"],
    "concepts/blog-automation.md": ["Blogger", "Blog", "Trends", "SEO"],
    "concepts/database-sync.md": ["Sync", "DB", "SQL", "Database", "Graphify", "csn"],
    "entities/lowy.md": ["Lowy", "Personal"]
};

function parseClaims(filePath) {
    const claims = [];
    if (!fs.existsSync(filePath)) return claims;
    const content = fs.readFileSync(filePath, 'utf8');
    
    const claimPattern = /(CLAIM-\w+):\s*(.*)/g;
    let match;
    
    while ((match = claimPattern.exec(content)) !== null) {
        const claimId = match[1];
        const summary = match[2].trim();
        
        const sourcePattern = new RegExp(`${claimId}.*?- \\*\\*source\\*\\*:\\s*(\`?.*?\`?)`, 's');
        const sourceMatch = content.match(sourcePattern);
        const source = sourceMatch ? sourceMatch[1] : "Unknown";
        
        claims.push({
            id: claimId,
            summary: summary,
            source: source,
            file: path.basename(filePath)
        });
    }
    return claims;
}

function updateWikiPage(wikiRelPath, claims) {
    const wikiPath = path.join(WIKI_DIR, wikiRelPath);
    if (!fs.existsSync(wikiPath)) {
        // Ensure directory exists
        fs.mkdirSync(path.dirname(wikiPath), { recursive: true });
        // Create basic template
        const title = path.basename(wikiRelPath, '.md').toUpperCase();
        fs.writeFileSync(wikiPath, `# [[${title}]]\n\nAuto-generated wiki page.\n\nSource: ${wikiRelPath}#L1\n`, 'utf8');
    }

    let content = fs.readFileSync(wikiPath, 'utf8');
    const header = "## 🧠 Technical Claims (K-Layer)";
    const tableHeader = "| Claim ID | Summary | Source |\n| :--- | :--- | :--- |";
    
    if (!content.includes(header)) {
        if (content.includes("Source:")) {
            content = content.replace("Source:", `${header}\n\n${tableHeader}\n\nSource:`);
        } else {
            content += `\n\n${header}\n\n${tableHeader}\n`;
        }
    }

    const rows = Array.from(claims).sort((a, b) => a.id.localeCompare(b.id))
        .map(c => `| ${c.id} | ${c.summary} | [${c.file}](file:///.agent/knowledge/notes/${c.file}) |`);
    
    const tableContent = rows.join('\n');
    const fullTablePattern = new RegExp(`${header.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}.*?\\| :--- \\| :--- \\|\\n(.*?)(?=\\n\\n##|\\n\\nSource:|$)`, 's');
    const newContent = content.replace(fullTablePattern, `${header}\n\n${tableHeader}\n${tableContent}`);
    
    fs.writeFileSync(wikiPath, newContent, 'utf8');
    console.log(`Updated ${wikiRelPath} with ${claims.length} claims`);
}

function generateGraph(allClaims) {
    const graphPath = path.join(WIKI_DIR, 'graph.md');
    fs.mkdirSync(WIKI_DIR, { recursive: true });

    let mermaid = "graph TD\n    K[K-Layer Wiki] --> D[Domains]\n";
    const domains = {};

    allClaims.forEach(c => {
        const domain = c.file.replace('.md', '');
        if (!domains[domain]) domains[domain] = [];
        domains[domain].push(c);
    });

    Object.entries(domains).forEach(([domain, claims]) => {
        mermaid += `    D --> ${domain.replace(/-/g, '_')}[${domain}]\n`;
        claims.slice(0, 5).forEach(c => { // Limit to 5 per domain for readability
            mermaid += `    ${domain.replace(/-/g, '_')} --> ${c.id.replace(/-/g, '_')}[${c.id}]\n`;
        });
    });

    const content = `# 📊 Knowledge Graph\n\n이 그래프는 K-Layer의 지식 구조를 시각화합니다.\n\n\`\`\`mermaid\n${mermaid}\`\`\`\n\nSource: wiki/graph.md#L1\n`;
    fs.writeFileSync(graphPath, content, 'utf8');
    console.log(`Generated wiki/graph.md with ${allClaims.length} claims`);
}

function main() {
    if (!fs.existsSync(KNOWLEDGE_DIR)) {
        console.error(`Knowledge directory not found: ${KNOWLEDGE_DIR}`);
        return;
    }

    const allClaims = [];
    const files = fs.readdirSync(KNOWLEDGE_DIR).filter(f => f.endsWith('.md'));
    files.forEach(file => {
        allClaims.push(...parseClaims(path.join(KNOWLEDGE_DIR, file)));
    });
    
    console.log(`Found ${allClaims.length} total claims across all notes.`);
    
    // Distribute claims
    const wikiUpdates = {};
    allClaims.forEach(claim => {
        let categorized = false;
        const textToCheck = (claim.summary + claim.id + claim.file).toLowerCase();
        
        for (const [wikiRelPath, keywords] of Object.entries(MAPPING)) {
            if (keywords.some(kw => textToCheck.includes(kw.toLowerCase()))) {
                if (!wikiUpdates[wikiRelPath]) wikiUpdates[wikiRelPath] = [];
                wikiUpdates[wikiRelPath].push(claim);
                categorized = true;
                break;
            }
        }
        
        if (!categorized) {
            const defaultPage = "concepts/n-slash-a-b-i.md";
            if (!wikiUpdates[defaultPage]) wikiUpdates[defaultPage] = [];
            wikiUpdates[defaultPage].push(claim);
        }
    });

    for (const [wikiRelPath, claims] of Object.entries(wikiUpdates)) {
        const uniqueClaims = Array.from(new Map(claims.map(c => [c.id, c])).values());
        updateWikiPage(wikiRelPath, uniqueClaims);
    }

    generateGraph(allClaims);
}

main();
