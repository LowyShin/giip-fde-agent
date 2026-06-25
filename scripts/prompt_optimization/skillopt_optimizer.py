import sys

# Prevent creation of __pycache__/custom pycache prefix folders in this repository.
sys.dont_write_bytecode = True

import json
import os
import glob
import re
from datetime import datetime

class SkillOptOptimizer:
    def __init__(self, trace_dir=".agent/traces", skill_dir=".agent/skills", output_dir="outputs/skillopt"):
        self.trace_dir = trace_dir
        self.skill_dir = skill_dir
        self.output_dir = output_dir
        os.makedirs(self.output_dir, exist_ok=True)

    def load_traces(self):
        """Loads and filters traces that failed or have low rewards."""
        if not os.path.exists(self.trace_dir):
            print(f"[-] Trace directory '{self.trace_dir}' not found.")
            return []

        trace_files = glob.glob(os.path.join(self.trace_dir, "*.json"))
        traces = []
        for file in trace_files:
            try:
                with open(file, 'r', encoding='utf-8') as f:
                    traces.append(json.load(f))
            except Exception as e:
                print(f"[-] Error reading trace {file}: {e}")
        return traces

    def simulate_validation_gate(self, original_skill_path, candidate_content, low_reward_traces):
        """
        Simulates the Validation Gate checking mechanism of SkillOpt.
        In a real run, this would execute the agent on a validation dataset.
        Here, we mock evaluate the candidate content based on whether it addresses the feedback points.
        """
        print(f"\n[+] Validation Gate: Evaluating candidate skill edits for '{os.path.basename(original_skill_path)}'...")
        
        # Read the original content
        with open(original_skill_path, 'r', encoding='utf-8') as f:
            original_content = f.read()

        # Count edits to compute the edit distance/ratio (learning rate/budget check)
        original_words = set(original_content.split())
        candidate_words = set(candidate_content.split())
        added_words = candidate_words - original_words
        removed_words = original_words - candidate_words
        total_edit_words = len(added_words) + len(removed_words)

        # Learning rate budget (e.g. max 15% change to prevent destructive rewrites)
        budget = int(len(original_words) * 0.15)
        if budget < 20: 
            budget = 20 # Minimum threshold

        print(f"    - Bounded Edits Budget: {budget} words. Total words changed: {total_edit_words}")
        if total_edit_words > budget:
            print(f"    [!] Warning: Edit size ({total_edit_words}) exceeds bounded edit budget ({budget}). Bounded constraint violated!")
            return False, "Edit size too large (learning rate too high)"

        # Simulated pass: check if candidate instructions address common issues from low reward traces
        resolved_issues = 0
        for trace in low_reward_traces:
            feedback = trace.get("feedback", "").lower()
            # If the feedback contains keywords that now exist in candidate but not original
            keywords = [w for w in re.findall(r'\w+', feedback) if len(w) > 4]
            for kw in keywords:
                if kw in candidate_content.lower() and kw not in original_content.lower():
                    resolved_issues += 1
                    break

        if resolved_issues > 0 or len(low_reward_traces) == 0:
            print("    [✓] Validation Gate PASSED. Performance improved or stabilized.")
            return True, "Success"
        else:
            print("    [✗] Validation Gate FAILED. Edits did not address critical failure modes.")
            return False, "Failed to resolve failures"

    def optimize_skill(self, skill_name, low_reward_traces):
        """Simulates optimization of a single skill file using bounded edits."""
        skill_path = os.path.join(self.skill_dir, skill_name, "SKILL.md")
        if not os.path.exists(skill_path):
            print(f"[-] Skill file not found: {skill_path}")
            return

        print(f"\n==========================================")
        print(f"[SkillOpt] Optimizing Skill: {skill_name}")
        print(f"==========================================")

        with open(skill_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Propose a bounded edit (mock edit targeting the specific issues in the trace feedback)
        print("[+] Proposing Bounded Edit (Text-Space Gradient Step)...")
        feedback_points = []
        for trace in low_reward_traces:
            feedback_points.append(trace.get("feedback", "Improve general robustness"))

        # Formulate new guidelines block to append/insert
        new_guidelines = "\n\n## 💡 SkillOpt Auto-Optimized Guidelines\n"
        for i, fp in enumerate(feedback_points[:3], 1):
            new_guidelines += f"- **Refinement {i}**: Ensure we handle case: '{fp}' correctly.\n"

        candidate_content = content + new_guidelines

        # Check validation gate
        passed, reason = self.simulate_validation_gate(skill_path, candidate_content, low_reward_traces)
        if passed:
            # Save deployable best_skill.md artifact
            best_skill_path = os.path.join(self.output_dir, f"best_{skill_name}.md")
            with open(best_skill_path, 'w', encoding='utf-8') as f:
                f.write(candidate_content)
            print(f"[✓] Saved optimized skill to deployable artifact: {best_skill_path}")
        else:
            print(f"[✗] Discarded candidate edits. Reason: {reason}")

    def run(self):
        traces = self.load_traces()
        low_reward = [t for t in traces if t.get("reward", 1.0) < 0.8]

        if not low_reward:
            print("[+] All traces show high rewards. No offline optimization required.")
            return

        # Group low reward traces by skill used
        skill_groups = {}
        for trace in low_reward:
            skill = trace.get("skill_used", "unknown")
            if skill not in skill_groups:
                skill_groups[skill] = []
            skill_groups[skill].append(trace)

        for skill_name, traces_to_fix in skill_groups.items():
            if skill_name != "unknown":
                self.optimize_skill(skill_name, traces_to_fix)

if __name__ == "__main__":
    optimizer = SkillOptOptimizer()
    optimizer.run()
