import sys
import os

try:
    import agentlightning as agl
except ImportError:
    print("Error: Agent Lightning is not installed.")
    print("Please run: pip install agentlightning")
    sys.exit(1)

def start_dashboard():
    print("Starting Agent Lightning Dashboard...")
    # This usually starts the local server and web UI
    # In agentlightning 1.0+, you can use the CLI or this programmatic way
    os.system("agl-dashboard")

if __name__ == "__main__":
    start_dashboard()
