---
description: Trace a task using Agent Lightning
---

> [!TIP]
> This workflow is built for tracing. Always ensure you are in a `/native-trace` or `/agl-trace` session to capture optimization data.

// turbo-all
1.  Navigate to the repository root in WSL2.
2.  Activate the virtual environment:
    ```bash
    source .agl_venv/bin/activate
    ```
3.  Define a task you want to trace. For example, run the example agent:
    ```bash
    python examples/agl/example_agent.py --prompt "Fix this bug in my Python code"
    ```
4.  Launch the dashboard to see the rollout trace:
    ```bash
    agl-dashboard
    ```
5.  Reflect on the captured spans and modify prompts in `.agent/skills/` as needed.
