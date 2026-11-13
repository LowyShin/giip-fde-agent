---
name: design-md
description: Discovery and integration of professional design systems from multiple platforms (designmd.ai, designmd.app, getdesign.md, designmd.me, designbookmark.com). Use this when starting a project, updating UI, or requesting specific brand "looks" (Stripe, Vercel, etc.). Also use designbookmark.com/motion when the user wants animated/motion UI components (buttons, tooltips, dropdowns, sliders) implemented in code.
---

# design-md (Consolidated)

This skill enables the agent to scout and apply the best design systems from the entire `design-md` ecosystem.

## 1. Discovery Strategy (Source Selection)

| User Intent | Platform | Method |
| :--- | :--- | :--- |
| **Famous Brand Look** (Stripe, Apple, etc.) | [getdesign.md](https://getdesign.md) | `npx getdesign add <brand>` |
| **CLI Automation / SaaS Kits** | [designmd.ai](https://designmd.ai) | `npx designmd download <id>` |
| **Community Library (400+ kits)** | [designmd.app](https://designmd.app) | Browser Search / Scrape |
| **Existing Site Replication** | [designmd.me](https://designmd.me) | URL-to-Markdown Generation |
| **Agent Setup/Rules** (Cursor, Claude) | [designmd.app/guides](https://designmd.app/en/guides) | Context-specific file creation |
| **Motion / Animated Components** | [designbookmark.com/motion](https://designbookmark.com/motion) | Browse live components, copy one for Claude/Codex, paste into the project and implement it |

## 2. Interactive Flow

### A. Scouting Phase
When a user asks for a design, scout multiple sources:
1.  **Search CLI**: `npx designmd search "<query>"`
2.  **Brand Check**: If a brand name is mentioned, check [getdesign.md](https://getdesign.md).
3.  **Library Check**: Browse [designmd.app](https://designmd.app) via `llms.txt` or browser tool.
4.  **Motion Check**: If the request involves animation or interactive micro-interactions (e.g. "make this button feel alive", "add a playful dropdown"), browse [designbookmark.com/motion](https://designbookmark.com/motion) — its components run live in the browser, so the user can see the exact motion before choosing.

Showcase 3-5 results with their source, description, and preview link.

### B. Selection & Setup
Guide the user through setup based on the chosen platform:
- **getdesign.md**: CLI command is free and instant.
- **designmd.ai**: Check for API Key requirement and guide setup.
- **designmd.me**: If a URL is provided, offer to visit the site and generate the markdown.
- **designbookmark.com/motion**: Each component page offers a copy action made for Claude/Codex. Copy it, paste it into the project context, and implement the component following that spec. Keep the motion parameters (spring, timing, easing) as specified; do not approximate them from the preview alone. Examples on the page (checked 2026-11-13): Morph tooltip, Spring dropdown, Jelly slider, Pull to refresh, Command palette, OTP code, Toggle switch.

### C. Agent Integration
After applying `DESIGN.md`, reference [designmd.app/guides](https://designmd.app/en/guides) to generate:
- `.cursorrules` (for Cursor)
- `CLAUDE.md` (for Claude Code)
- `.windsurfrules` (for Windsurf)

## 3. Usage Guidelines
- **Always Scout**: Never settle for one source; check the brand collection vs the automated kits.
- **Preview First**: Provide the `designmd.ai` or `designmd.app` link for visual preview before implementation.
- **Design Consistency**: Once a kit is applied, strictly enforce its tokens in all CSS and component files.
