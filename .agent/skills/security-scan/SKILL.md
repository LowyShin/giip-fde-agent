---
name: security-scan
description: Performs a rapid security sweep for secrets, API keys, and common vulnerabilities using cross-platform platform tools.
triggers: security scan, 보안 점검, 취약점 점검, scan for secrets, check keys
---

# security-scan Skill

This skill performs a fast, grep-based security scan of the repository. It focuses on identifying hardcoded secrets and common misconfigurations.

## 🛠️ Usage

Trigger this skill before any git push or after significant code changes.

### Scan Patterns

The following patterns are scanned using the `grep_search` platform tool:

| Category | Pattern | Description |
| :--- | :--- | :--- |
| **Secrets** | `sk-[a-zA-Z0-9]{48}` | OpenAI API Keys |
| **Secrets** | `ghp_[a-zA-Z0-9]{36}` | GitHub Personal Access Tokens |
| **Secrets** | `AKIA[0-9A-Z]{16}` | AWS Access Key IDs |
| **Config** | `\.env$` | Unencrypted environment files |
| **Vulnerability** | `eval\(` | Dangerous eval usage |
| **Vulnerability** | `dangerouslySetInnerHTML` | Potential XSS (React) |

## 💻 Cross-Platform Implementation

This skill uses the **platform-native `grep_search` API**, which is optimized for Windows, Mac, and Linux. No extra binary installation (like `rg`) is required.

### Example Scan Execution

```javascript
// Step 1: Detect current OS (via env-check)
// Step 2: Use grep_search with absolute path
grep_search({
  Query: "sk-[a-zA-Z0-9]{48}",
  SearchPath: "/absolute/path/to/project",
  IsRegex: true
});
```

## 🛡️ Response Actions

If a match is found:
1.  **Stop**: Do not proceed with the task until the vulnerability is addressed.
2.  **Alert**: Report the exact file and line number to the user.
3.  **Fix**: Recommend moving the secret to an environment variable or using a secret manager.
