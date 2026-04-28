# Custom Workflow: /gaupdate

This workflow monitors specified repositories for new or updated Gemini skills and integrates them into the agent.

## Workflow Steps

1. **Read Configuration**: Load the list of source URLs from `.agent/config/update_urls.json`.
2. **Scan Repositories**:
   - For each URL, use `browser_subagent` to check for new directories in `skills/`.
   - Compare with local directories in `.agent/skills/`.
3. **Download & Integrate**:
   - For any new or significantly updated skills, fetch the `SKILL.md` and associated files.
   - Save them to the corresponding `.agent/skills/{skill-name}/` directory.
4. **Update Registry**:
   - Update `lastUpdate` timestamp in `update_urls.json`.
5. **Summarize**:
   - Report the number of new/updated skills to the user.

## Trigger
Use the slash command: `/gaupdate`
