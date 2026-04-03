import argparse
import os

try:
    import agentlightning as agl
except ImportError:
    print("Error: Agent Lightning is not installed.")
    print("Please run: /agl-init")
    exit(1)

# A sample prompt template that can be optimized
system_template = agl.PromptTemplate(
    "You are a helpful coding assistant. Solve the following task: {{user_input}}",
    role="system"
)

@agl.rollout
def solve_task(user_input):
    """
    Simulates an agent solving a task.
    In a real scenario, this would call an LLM (e.g., via OpenAI API).
    """
    print(f"Solving: {user_input}")
    
    # Render the optimizable prompt
    full_prompt = system_template.render(user_input=user_input)
    print(f"Generated Prompt: {full_prompt}")
    
    # Simulate a result
    result = f"DONE: {user_input} has been processed."
    
    # Emit a reward (feedback)
    # 1.0 = Success, 0.0 = Failure
    agl.emit_reward(1.0)
    
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", type=str, default="Write a hello world script")
    args = parser.parse_args()
    
    result = solve_task(args.prompt)
    print(f"Result: {result}")
