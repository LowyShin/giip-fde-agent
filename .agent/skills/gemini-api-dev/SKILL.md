---
name: gemini-api-dev
description: Guides the usage of the Google Gemini API with the Gen AI SDK. Covers common tasks like client initialization, multimodal usage (images, video, audio, files), chat, function calling, structured output, and safety settings. Supports Python, JS/TS, Go, Java, and C#.
compatibility: Requires Gemini API key or Google Cloud credentials.
---

# Gemini API Development

Access Google's latest generative models (Gemini 3.1 Pro, Gemini 3 Flash, etc.) through the unified Google Gen AI SDK.

## Core Directives

- **Unified SDK**: ALWAYS use the Gen AI SDK library (`google-genai` for Python, `@google/genai` for JS/TS, `google.golang.org/genai` for Go, `com.google.genai:google-genai` for Java, `Google.GenAI` for C#).
- **Legacy SDKs**: DO NOT use the legacy library `google-generativeai`.
- **Model Selection**: Prefer `gemini-3.1-pro-preview` for complex tasks and `gemini-3-flash-preview` for speed and efficiency.

## Setup

### Python
```bash
pip install google-genai
```

### JavaScript/TypeScript
```bash
npm install @google/genai
```

### Go
```bash
go get google.golang.org/genai
```

### Java
- groupId: `com.google.genai`, artifactId: `google-genai`
- Latest version can be found here: https://central.sonatype.com/artifact/com.google.genai/google-genai/versions (let's call it `LAST_VERSION`) 
- Install in `build.gradle`:
```gradle
implementation("com.google.genai:google-genai:${LAST_VERSION}")
```

### C#/.NET
```bash
dotnet add package Google.GenAI
```

## Initialization

Initialize the client using an API Key.

```python
from google import genai

client = genai.Client(api_key='YOUR_API_KEY')
```

## Common Tasks

### Text Generation
```python
response = client.models.generate_content(
    model='gemini-2.0-flash', 
    contents='Tell me a story about a brave knight.'
)
print(response.text)
```

### Multimodal (Images, Video, Audio)
Gemini can process multiple modalities.

**Image**:
```python
from PIL import Image
img = Image.open('image.jpg')
response = client.models.generate_content(
    model='gemini-2.0-flash',
    contents=['Describe this image:', img]
)
```

**Video/Audio/PDF**:
Upload files first using the File API before processing.

```python
file = client.files.upload(path='video.mp4')
response = client.models.generate_content(
    model='gemini-2.0-flash',
    contents=['Summarize this video:', file]
)
```

### Chat sessions
Maintain state across multiple turns.

```python
chat = client.chats.create(model='gemini-2.0-flash')
response = chat.send_message('Hi, I am Bob.')
response = chat.send_message('What is my name?')
```

### Function Calling
Allow the model to interact with external tools or APIs.

```python
def get_weather(location: str):
    return f"The weather in {location} is sunny."

client = genai.Client(api_key='YOUR_API_KEY')
response = client.models.generate_content(
    model='gemini-2.0-flash',
    contents='What is the weather in London?',
    config={'tools': [get_weather]}
)
```

### Structured Output (JSON)
Force the model to return data in a specific JSON schema.

```python
from pydantic import BaseModel

class Recipe(BaseModel):
    name: str
    ingredients: list[str]

response = client.models.generate_content(
    model='gemini-2.0-flash',
    contents='Give me a recipe for cookies',
    config={
        'response_mime_type': 'application/json',
        'response_schema': Recipe
    }
)
recipe = response.parsed
```

## API spec & Documentation (source of truth)

When implementing or debugging API integration, refer to the official Gemini API documentation:
- **Main Documentation Site**: https://ai.google.dev/gemini-api/docs
- **API Reference**: https://ai.google.dev/api

> [!TIP]
> **Use the Developer Knowledge MCP Server**: If the `search_documents` or `get_document` tools are available, use them to find and retrieve official documentation for Gemini API directly within the context. This is the preferred method for getting up-to-date API details and code snippets.
