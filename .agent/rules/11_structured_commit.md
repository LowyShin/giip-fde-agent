# Structured Commit Protocol

To preserve architectural context and decision-making history, all agents SHOULD include structured trailers in their git commit messages.

## 📝 Format Guidelines

The following trailers should be included when applicable:

- `Constraint`: Technical or business constraints that forced this specific implementation.
- `Rejected`: Alternative approaches that were considered but discarded (and why).
- `Directive`: Specific user instructions or project rules that influenced the change.
- `Confidence`: Implementation confidence level (Low/Mid/High).
- `Scope-risk`: Potential side effects or risks associated with the change (Narrow/Wide).
- `Not-tested`: Any parts of the change that could not be verified automatically.

## 💡 Example

```text
fix(auth): prevent silent session drops during long-running ops

Auth service returns inconsistent status codes on token expiry, 
so the interceptor catches all 4xx and triggers inline refresh.

Constraint: Auth service does not support token introspection
Rejected: Extend token TTL to 24h | security policy violation
Confidence: High
Scope-risk: Narrow
```
