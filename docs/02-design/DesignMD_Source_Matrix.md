# Design MD Source Matrix

This guide helps you choose the right platform for your design needs. The agent will use this matrix to guide you during the discovery phase.

| Platform | Best For... | Features | How we use it |
| :--- | :--- | :--- | :--- |
| **[designmd.ai](https://designmd.ai)** | **Automation & SaaS** | CLI support, Pro kits, trending search | `npx designmd download` |
| **[designmd.app](https://designmd.app)** | **Library & Guides** | 423+ kits, Agent setup guides (Claude/Cursor) | Research & `.cursorrules` creation |
| **[getdesign.md](https://getdesign.md)** | **Brand Replication** | Famous brands (Stripe, Notion, Apple) | `npx getdesign add <brand>` |
| **[designmd.me](https://designmd.me)** | **Custom Generation** | URL-to-Markdown, Text-to-Markdown | Live scanning of URLs |
| **[designbookmark.com/motion](https://designbookmark.com/motion)** | **Motion Components** | Live animated components (~48), copy made for Claude/Codex | Copy a component, paste it into the project, implement it as specified |

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
