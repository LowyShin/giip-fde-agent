# 🚀 Quick Start Guide

A friendly beginner's guide for those new to AI development tools.

> **Who is this guide for?**  
> - First-time users of AI coding tools
> - People who don't know what Antigravity or Cursor is
> - Anyone who feels overwhelmed about where to start

---

## 📚 Table of Contents
1. [What is GIIP Agent System?](#-what-is-giip-agent-system)
2. [Preparing Required Tools](#️-preparing-required-tools)
3. [Downloading and Setting Up the Repository](#-downloading-and-setting-up-the-repository)
4. [Choosing and Installing an AI Tool](#-choosing-and-installing-an-ai-tool)
5. [Starting Your First Conversation](#-starting-your-first-conversation)
6. [Next Steps](#-next-steps)

---

## 🤔 What is GIIP Agent System?

**GIIP Agent System** is an intelligent assistant system where AI helps you write code.

### What can it do?
- ✅ Automatically perform complex development tasks
- ✅ Review and suggest code improvements
- ✅ Find and fix bugs
- ✅ Generate documentation automatically
- ✅ Write test code

### How does it work?
1. **Orchestrator (Conductor)**: Receives and analyzes your requests
2. **Specialized Agents (Experts)**: Each handles their specialty (development, testing, review, etc.)
3. **Collaboration**: Multiple experts work together to create the best results

---

## 🛠️ Preparing Required Tools

### Step 1: Install Basic Tools

These tools need to be installed by all users first.

#### Windows Users
```powershell
# 1. Install PowerShell 7 (Windows 10/11)
winget install --id Microsoft.PowerShell --source winget

# 2. Check Node.js installation (if not installed, download from https://nodejs.org)
node --version

# 3. Check Git installation (if not installed, download from https://git-scm.com)
git --version
```

#### Mac/Linux Users
```bash
# 1. Check Node.js installation
node --version

# 2. Check Git installation
git --version
```

> 💡 **If installation is needed**: Check the [Tools Download Page](TOOLS_DOWNLOAD.md) for detailed installation instructions.

---

## 📥 Downloading and Setting Up the Repository

### Method 1: Using Git (Recommended)

```bash
# 1. Navigate to your desired folder
cd Documents/Projects

# 2. Clone the repository
git clone https://github.com/LowyShin/giip-dev-agent.git

# 3. Enter the folder
cd giip-dev-agent
```

### Method 2: Download ZIP File

1. Visit the [GitHub Repository](https://github.com/LowyShin/giip-dev-agent)
2. Click the green "Code" button
3. Select "Download ZIP"
4. Extract the downloaded file
5. Navigate to the extracted folder

---

## 🤖 Choosing and Installing an AI Tool

Choose the tool that fits your situation!

### 🎯 Recommended Selection Guide

#### For Beginners: Antigravity (Free) ⭐
- **Pros**: Korean support, easy to use, free
- **Cons**: Requires Gemini API Key
- **Download**: [Antigravity Manager](https://agm.littleworld.net/)

#### For Professionals: Cursor ($20/month)
- **Pros**: Powerful features, fast speed
- **Cons**: Paid (free trial available)
- **Download**: [Cursor](https://www.cursor.com/)

#### For VS Code Users: GitHub Copilot ($10/month)
- **Pros**: Perfect VS Code integration
- **Cons**: Paid (free for students/open source contributors)
- **Install**: As VS Code extension

> 📖 **More Tool Comparisons**: Check the full list on the [Tools Download Page](TOOLS_DOWNLOAD.md).

---

## 🎬 Getting Started with Antigravity (Recommended)

### Step 1: Get API Key

1. Visit [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Get API Key" or "Create API Key"
4. Copy the generated key (e.g., `AIzaSy...`)

### Step 2: Install Antigravity

1. [Download Antigravity Manager](https://agm.littleworld.net/)
2. Run the installer
3. Launch Antigravity Manager after installation

### Step 3: Project Setup

#### A. Applying to Existing Project
```bash
# 1. Navigate to your project folder
cd my-project-folder

# 2. Copy GIIP Agent files (PowerShell)
# Copy excluding .git folder
Copy-Item -Path "giip-dev-agent\.agent" -Destination "." -Recurse -Force
Copy-Item -Path "giip-dev-agent\GEMINI.md" -Destination "." -Force
Copy-Item -Path "giip-dev-agent\.cursorrules" -Destination "." -Force
```

#### B. Starting New Project
```bash
# Use GIIP Agent repository as-is for your project
cd giip-dev-agent
```

### Step 4: API Key Setup

```bash
# 1. Copy settings.json.sample file
cd .agent
copy settings.json.sample settings.json

# 2. Open settings.json and enter your API Key
# Replace "YOUR_GEMINI_API_KEY_HERE" with your actual key
```

Or open `.agent/settings.json` in your editor and modify as follows:
```json
{
  "apiKey": "AIzaSyYourActualKey",
  "model": "gemini-2.0-flash-exp"
}
```

---

## 💬 Starting Your First Conversation

### In Antigravity

1. Launch Antigravity Manager
2. Select or drag-and-drop your project folder
3. Enter this message in the chat:

```
Hi! You are the orchestrator.
First, analyze what this project does,
and tell me what I can do.
```

### Example Questions

#### Project Analysis
```
Analyze the structure of this project and explain its main features.
```

#### Developing New Features
```
You are the orchestrator.
I want to add a user login feature,
analyze the required tasks and delegate to the appropriate agents.
```

#### Bug Fixing
```
An error occurs during login,
use the systematic-debugging skill to find the cause.
```

#### Code Review
```
Review the code I recently wrote and suggest improvements.
```

---

## 🎓 Basic Usage Patterns

### 1. Starting in Orchestrator Mode

```
You are the orchestrator.
Check your role and analyze the tasks below,
then delegate to the appropriate team members.

-- Task Details --
[Describe what you want to do here]
```

### 2. Using PDCA Methodology

For complex tasks, proceed step by step:

```
/pdca plan user-authentication-feature
```
→ Planning

```
/pdca design user-authentication-feature
```
→ Design document creation

```
/pdca do user-authentication-feature
```
→ Implementation

```
/pdca analyze user-authentication-feature
```
→ Verification

### 3. Automated Mode (Advanced)

Execute tasks automatically in the background:

```powershell
# Run in PowerShell
.\.agent\scripts\launch_subsession.ps1
```

Or run automatically every 5 minutes:
```cmd
.\auto_agent.bat
```

---

## 🎯 Next Steps

Congratulations! 🎉 You've started your first AI agent conversation.

### Learn More

1. **[Antigravity Detailed Guide](ANTIGRAVITY_USAGE_GUIDE.md)**: PDCA methodology and advanced features
2. **[Prompt Examples](prompt_example.md)**: Effective questioning methods
3. **[System Guide](.agent/README.md)**: In-depth learning of the agent system

### Frequently Asked Questions

#### Q: I'm worried about API usage costs.
A: Google Gemini API has a generous free quota. For typical development purposes, the free tier is sufficient.

#### Q: Which tool is the best?
A: 
- **Starting for free**: Antigravity + Gemini API
- **Professional developers**: Cursor or GitHub Copilot
- **VS Code users**: GitHub Copilot

#### Q: I'm not good at English, is that okay?
A: Yes! This system is designed with Korean-First principle. However, most AI tools work well in English too. You can communicate in your preferred language.

#### Q: What should I do if an error occurs?
A: 
1. Post a question on the [Issues page](https://github.com/LowyShin/giip-dev-agent/issues)
2. Ask the AI with the error message
3. Get support from the [GIIP Official Website](https://giip.littleworld.net/)

---

## 💡 Useful Tips

### 1. Ask Clearly
❌ Bad: "Fix this"
✅ Good: "When I click the login button, I get a 404 error. Find the cause and fix it."

### 2. Proceed Step by Step
Break down complex tasks into small steps.

### 3. Request Verification
```
When you're done, run tests to verify it works properly.
```

### 4. Specify Code Style
```
This project uses TypeScript and React,
write using functional components.
```

---

## 🆘 Need Help?

- **GitHub Issues**: [Report a Problem](https://github.com/LowyShin/giip-dev-agent/issues)
- **Official Website**: [https://giip.littleworld.net/](https://giip.littleworld.net/)
- **Community**: [GitHub Discussions](https://github.com/LowyShin/giip-dev-agent/discussions)

---

**Last Updated**: 2026-02-07  
**Written by**: GIIP Agent System Team

---

## 📝 License

This project follows the Apache 2.0 License.
For more information, see the [LICENSE](LICENSE) file.
