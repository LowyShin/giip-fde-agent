# Design MD Source Matrix

This guide helps you choose the right platform for your design needs. The agent will use this matrix to guide you during the discovery phase.

| Platform | Best For... | Features | How we use it |
| :--- | :--- | :--- | :--- |
| **[designmd.ai](https://designmd.ai)** | **Automation & SaaS** | CLI support, Pro kits, trending search | `npx designmd download` |
| **[designmd.app](https://designmd.app)** | **Library & Guides** | 423+ kits, Agent setup guides (Claude/Cursor) | Research & `.cursorrules` creation |
| **[getdesign.md](https://getdesign.md)** | **Brand Replication** | Famous brands (Stripe, Notion, Apple) | `npx getdesign add <brand>` |
| **[designmd.me](https://designmd.me)** | **Custom Generation** | URL-to-Markdown, Text-to-Markdown | Live scanning of URLs |
| **[designbookmark.com/motion](https://designbookmark.com/motion)** | **Motion Components** | Live animated components (~48), copy made for Claude/Codex | Copy a component, paste it into the project, implement it as specified |

## GitHub Design Resources for Agents

Open-source design tools for agents on GitHub (all active, openly licensed — verified 2026-11-20). The platforms above are DESIGN.md sources; these are skills, a spec, a design system, and integration/verification tools.

| Resource | Best For... | Features | How we use it |
| :--- | :--- | :--- | :--- |
| **[DESIGN.md spec (Google Labs)](https://github.com/google-labs-code/design.md)** | **The DESIGN.md format itself** | The specification for describing a visual identity to coding agents | Canonical reference when authoring or validating a project's DESIGN.md |
| **[UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** | **Design intelligence skill** | 80 UI styles, 192 color palettes, 74 font pairings in one skill | Pick style/palette/font candidates from the skill data and reflect them in DESIGN.md tokens |
| **[frontend-design (Anthropic)](https://github.com/anthropics/skills/tree/main/skills/frontend-design)** | **Frontend design skill** | Anthropic's official skill for distinctive, non-templated interfaces | Upstream original of the skill vendored in this repo; reference for updates |
| **[canvas-design (Anthropic)](https://github.com/anthropics/skills/tree/main/skills/canvas-design)** | **Poster & graphic design skill** | Anthropic's official skill | Upstream original of the skill vendored in this repo |
| **[pptx (Anthropic)](https://github.com/anthropics/skills/tree/main/skills/pptx)** | **Presentation skill** | Anthropic's official skill | Upstream original of the skill vendored in this repo |
| **[Astryx (Meta)](https://github.com/meta/astryx)** | **Design system** | Meta's open-source design system, designed to be agent ready | Reference for component structure and token organization |
| **[Figma Context MCP](https://github.com/GLips/Figma-Context-MCP)** | **Figma → agent bridge** | MCP server that gives agents Figma layout information | Pull layout context directly from Figma when implementing from a design |
| **[agent-browser (Vercel)](https://github.com/vercel-labs/agent-browser)** | **Result verification** | Browser automation CLI for AI agents | Open the built UI in a browser and verify the rendered result |

## Recommendation Guide

- **"I want my site to look like Stripe or Vercel."**
  - -> **Source**: [getdesign.md](https://getdesign.md)
  - -> **Action**: We'll use `npx getdesign add stripe`.

- **"Find me a clean, modern dashboard kit."**
  - -> **Source**: [designmd.ai](https://designmd.ai)
  - -> **Action**: We'll search for "dashboard" and show you trending options.

- **"How do I set up these design rules for Cursor?"**
  - -> **Source**: [designmd.app/guides](https://designmd.app/en/guides)
  - -> **Action**: I will fetch the specific guide and create a `.cursorrules` file for you.

- **"Make my site look like this example I found: [URL]."**
  - -> **Source**: [designmd.me](https://designmd.me)
  - -> **Action**: I'll visit the site and generate a custom `DESIGN.md` for our project.

- **"Give this button/dropdown a lively spring motion."**
  - -> **Source**: [designbookmark.com/motion](https://designbookmark.com/motion)
  - -> **Action**: I'll show live-preview candidates (e.g. Spring dropdown, Jelly slider, Morph tooltip), then implement the one you pick from its copy-for-Claude/Codex spec.
