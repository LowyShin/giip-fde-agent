---
name: gstack-security
description: |
  Chief Security Officer (CSO) logic for security audits. Use to find and fix security vulnerabilities.
  Inspired by gstack's /cso.

  Use proactively during the Review phase or when working on sensitive code (auth, database, user data).

  Triggers: cso, security audit, vulnerability, OWASP, STRIDE, threat model, exploit,
  보안 감사, 취약점, 보안 점검, 보안 리포트
---

# Gstack Security Analysis (CSO)

> "Zero-noise, high-confidence security findings with concrete exploit scenarios."

## 1. Methodology: OWASP Top 10 + STRIDE

When performing a security scan, use the following frameworks to identify risks:

- **STRIDE**: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege.
- **OWASP Top 10**: Broken Access Control, Cryptographic Failures, Injection, Insecure Design, etc.

## 2. Zero-Noise Filtering

To ensure actionable findings, apply the following filters:

- **Independent Verification**: Every finding must be independently verified by tracing the code path.
- **Confidence Gate**: Only report findings with **8/10+ confidence**.
- **Exclude False Positives**: Ignore known false positives (e.g., test files, internal-only tools, etc.).

## 3. Exploit Scenario Requirement

Every security finding must include:

1. **Vulnerability Type**: (e.g., SQL Injection, XSS, CSRF).
2. **Impacted File/Line**: Precise location in the codebase.
3. **Exploit Scenario**: A concrete description of how an attacker could exploit this.
4. **Recommended Fix**: Specific code changes to mitigate the risk.

## 4. Usage Table

| Category | Action |
|----------|--------|
| `cso scan` | Run a full security audit on the current scope. |
| `threat model` | Generate a STRIDE threat model for the current feature design. |
| `exploit {finding}` | Generate a detailed exploit scenario for a specific finding. |
