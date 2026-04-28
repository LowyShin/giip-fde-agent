# Design: Gemini Skills Integration & /gaupdate Workflow

## 1. Overview
This feature integrates high-quality Gemini-related skills from external repositories and provides a mechanism to keep them updated.

## 2. Component Design

### 2.1 Configuration (`.agent/config/update_urls.json`)
Stores the list of source URLs and metadata about the last update.
```json
{
  "sources": [
    {
      "id": "google-gemini-skills",
      "url": "https://github.com/google-gemini/gemini-skills",
      "description": "Official Gemini Skills"
    }
  ],
  "lastUpdate": "2026-04-21T18:05:00Z"
}
```

### 2.2 Workflow (`.agent/workflows/gaupdate.md`)
The `/gaupdate` command will be defined as a workflow that:
1. Reads the source list.
2. Uses the `browser_subagent` to scan repositories for new subdirectories in `skills/` (or similar).
3. Compares found skills with the local `.agent/skills/` directory.
4. Downloads `SKILL.md` and associated files for new skills.
5. Updates the local skill registry.

### 2.3 Initial Skills to Integrate
From `google-gemini/gemini-skills`:
- `gemini-api-dev`
- `gemini-interactions-api`
- `gemini-live-api-dev`
- `vertex-ai-api-dev`

## 3. Security Considerations
- Downloaded content should be stored in the isolated `.agent/skills/` directory.
- The workflow should inform the user before adding new skills that have scripts (to avoid arbitrary code execution).

## 4. Implementation Steps
1. Create config file.
2. Create workflow file.
3. Perform the first manual integration of the requested official skills.
4. Verify by running `/gaupdate`.
