---
description: Initialize Agent Lightning environment in WSL2
---

> [!TIP]
> This workflow should ideally be executed with tracing enabled (`/native-trace`) for future optimization and performance analysis.

1.  Open your WSL2 terminal.
2.  Clone the repository or navigate to the project root:
    ```bash
    cd /path/to/giip-dev-agent
    ```
3.  Create and activate a virtual environment:
    ```bash
    python3 -m venv .agl_venv
    source .agl_venv/bin/activate
    ```
4.  Install Agent Lightning:
    ```bash
    pip install agentlightning
    ```
5.  Verify the installation:
    ```bash
    agl-dashboard --help
    ```
6.  You can now use `/agl-trace` or run the example agent.
