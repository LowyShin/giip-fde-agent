import sys

# Prevent creation of __pycache__/custom pycache prefix folders in this repository.
sys.dont_write_bytecode = True

import json
import os
import glob
from datetime import datetime

def analyze_traces(trace_dir=".agent/traces"):
    """
    Analyzes execution traces in the specified directory.
    Identifies low-reward traces and provides a summary for optimization.
    """
    if not os.path.exists(trace_dir):
        print(f"Error: Trace directory '{trace_dir}' not found.")
        return

    traces = glob.glob(os.path.join(trace_dir, "*.json"))
    if not traces:
        print("No traces found for optimization.")
        return

    print(f"--- Native Agent Optimization Report ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')}) ---")
    print(f"Found {len(traces)} total traces.")

    low_performance_traces = []

    for trace_path in traces:
        try:
            with open(trace_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                reward = data.get("reward", 1.0)
                if reward < 0.8:
                    low_performance_traces.append(data)
        except Exception as e:
            print(f"Error reading {trace_path}: {e}")

    if not low_performance_traces:
        print("All traces satisfy the performance threshold (>= 0.8). No optimization needed.")
        return

    print(f"\n[!] Identified {len(low_performance_traces)} low-performance traces (Reward < 0.8):")
    
    for i, trace in enumerate(low_performance_traces, 1):
        skill = trace.get("skill_used", "unknown")
        reward = trace.get("reward", 0.0)
        task = trace.get("task", "No task description")
        feedback = trace.get("feedback", "No feedback provided")
        
        print(f"\n{i}. Trace ID: {trace.get('trace_id', 'unknown')}")
        print(f"   - Target Skill: {skill}")
        print(f"   - Reward Score: {reward}")
        print(f"   - Task: {task}")
        print(f"   - Feedback: {feedback}")
        print(f"   - Steps Captured: {len(trace.get('steps', []))}")

    print("\n--- Recommendation for AI Agent ---")
    print("Please use the 'prompt-optimizer' skill to analyze these traces.")
    print("For each trace, read the full JSON content and identify where the logic deviated.")
    print("Then, refine the corresponding SKILL.md file with clearer instructions and edge-case handling.")
    print("-------------------------------------")

if __name__ == "__main__":
    analyze_traces()
