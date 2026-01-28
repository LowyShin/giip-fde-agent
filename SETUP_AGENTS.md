# Agent Compatibility Setup

This project uses a standardized agent structure in `.agent/`.
Here is how to enable these superpowers in your AI tool of choice.

## 1. Cursor / Windsurf
**Status: Automatic**
- The project root contains `.cursorrules` which automatically loads `.agent/GEMINI.md` and skills.
- No action required.

## 2. GitHub Copilot
**Status: Automatic**
- The project root contains `COPILOT_INSTRUCTIONS.md`.
- Ensure your VS Code settings allow Copilot to read local files.

## 3. Claude Code
**Status: Plugin Required**
To use the skills in `.agent/skills` with Claude Code:

1. Install the Superpowers plugin (if not already installed):
   ```bash
   /plugin install superpowers@superpowers-marketplace
   ```
2. Point Claude to the local skills:
   - Claude Code usually looks for skills in the plugin directory, but you can explicitly mention:
     "Use the skills defined in ./.agent/skills/ for this task."

## 4. OpenCode / Codex
**Status: Manual Link Required**
These tools typically look for skills in your home directory (`~/.config/opencode/skills` or `~/.codex/skills`).

To use this project's skills:

**For OpenCode:**
```bash
# Link project skills to OpenCode's skill directory
ln -s $(pwd)/.agent/skills ~/.config/opencode/skills/antigravity-project
```

**For Codex:**
```bash
# Link project skills to Codex's skill directory
ln -s $(pwd)/.agent/skills ~/.codex/skills/antigravity-project
```
Once linked, you can ask the agent to "use the subagent-driven-development skill from antigravity-project".
