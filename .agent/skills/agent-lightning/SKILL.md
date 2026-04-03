# Agent Lightning Skill

Use Microsoft Agent Lightning to trace, optimize, and evaluate agent performance.

## 🎯 When to Use
- **Tracing**: Use when you want to record the exact steps, tool calls, and LLM prompts of an agent execution.
- **Optimization**: Use when you want to improve prompt templates automatically based on reward signals.
- **Evaluation**: Use when you want to visualize agent performance over multiple rollouts using the dashboard.

## ⚡ How to Trace
To trace a task, wrap the main function with the `@agl.rollout` decorator.

```python
import agentlightning as agl

@agl.rollout
def my_agent_task(prompt):
    # Agent logic here
    pass
```

## ⚡ How to Optimize Prompts
Use `agl.PromptTemplate` for parts of the prompt that you want the framework to optimize.

```python
template = agl.PromptTemplate(
    "You are an expert coder. Solve this: {{task}}",
    role="system"
)

# During rollout:
prompt = template.render(task="Write a binary search")
```

## 📊 Viewing Results
Run the dashboard to see traces and performance metrics:
```bash
python scripts/agl_dashboard.py
# or
agl-dashboard
```

## 🏗️ Environment
> [!IMPORTANT]
> Agent Lightning requires **Linux (WSL2 on Windows)**. All Python scripts using this skill should be executed in a WSL2 environment with `agentlightning` installed.
