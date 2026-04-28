---
name: gemini-live-api-dev
description: Guides the usage of the Gemini Live (Multimodal Live) API using the Gen AI SDK. Use when the user asks about real-time, bidirectional streaming of voice and video with Gemini. Covers configuration, session management, sending/receiving audio/video media, and tool integration.
compatibility: Requires Gemini API key or Vertex AI credentials. Currently available in Python and JavaScript SDKs.
---

# Gemini Live (Multimodal Live) API

The Multimodal Live API allows you to have low-latency, bidirectional, voice and video interactions with Gemini. Use this for building real-time voice assistants, interactive video applications, and other low-latency AI experiences.

## Key Features

- **Bidirectional Streaming**: Low-latency communication over WebSockets.
- **Audio & Video Support**: Send and receive real-time audio and video streams.
- **Multimodal Understanding**: The model "sees" and "hears" the stream directly.
- **Tool Integration**: Use function calling within live sessions.

## Core Directives

- **SDK Requirement**: Use the latest version of the Gen AI SDK (`google-genai` for Python, `@google/genai` for JS/TS).
- **WebSocket Protocol**: The API operates over WebSockets (WSS). The SDK abstracts this for you.
- **Model Selection**: Use models specifically optimized for live interactions, such as `gemini-2.0-flash-exp` (or later versions like `gemini-live-2.5-flash-native-audio`).

## Getting Started (Python)

### Installation
```bash
pip install google-genai
```

### Basic Session Management
```python
from google import genai

client = genai.Client(api_key='YOUR_API_KEY', http_options={'api_version': 'v1alpha'})

# Configures the live session
with client.live.connect(model='gemini-2.0-flash-exp', config={'generation_config': {'response_modalities': ['audio']}}) as session:
    # Send a message (text or audio bytes)
    session.send(input='Hello! How can you help me today?', end_of_turn=True)
    
    # Receive and process responses (text, audio, or tool calls)
    for message in session.receive():
        if message.text:
            print(f'Gemini: {message.text}')
        if message.server_content:
             # handle audio bytes from message.server_content.model_turn.parts
             pass
```

## Handling Media

### Sending Audio
Audio should be sent as raw bytes (16-bit PCM, 16kHz or 24kHz recommended).

```python
import sounddevice as sd

def audio_callback(indata, frames, time, status):
    # indata contains raw audio bytes
    session.send(input=indata.tobytes())

# In a separate thread or async loop:
with sd.InputStream(callback=audio_callback, channels=1, samplerate=16000):
    # keep session alive
    pass
```

### Receiving Audio
The model response includes audio bytes that can be played in real-time.

```python
for response in session.receive():
    if response.server_content and response.server_content.model_turn:
        for part in response.server_content.model_turn.parts:
            if part.inline_data:
                audio_bytes = part.inline_data.data
                # Play audio_bytes using your preferred library
```

## Tool Integration (Function Calling)

You can provide tools to the Live API just like the standard Gemini API.

```python
def turn_light_on():
  return {'status': 'light is on'}

config = {
    'tools': [turn_light_on],
    'generation_config': {'response_modalities': ['audio']}
}

with client.live.connect(model='gemini-2.0-flash-exp', config=config) as session:
    # Gemini will call the tool if the user asks
    for message in session.receive():
        if message.tool_call:
            # Handle the tool call manually or using SDK helpers
            pass
```

## Documentation & Best Practices

- **Official Web Docs**: https://ai.google.dev/gemini-api/docs/multimodal-live
- **Latency**: Keep buffers small and use high-performance audio/video libraries.
- **Safety**: Standard Gemini safety settings apply to the Live API.
- **Interruption**: Handle scenarios where the user interrupts the AI (the SDK provides `session.interrupt()`).
