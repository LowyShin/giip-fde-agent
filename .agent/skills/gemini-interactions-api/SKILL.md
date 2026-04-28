---
name: gemini-interactions-api
description: Master the Gemini Interaction artifacts. Use this when a user wants to know about the Interaction artifacts or if you want to know about the Interaction artifacts yourself.
compatibility: Requires active developer tools for Gemini API.
---

# Gemini Interaction Artifacts

Artifacts are specialized structured types designed to enhance human-AI interaction by representing complex information in a clear, interactive, and functional way. They help turn text-based responses into rich visual and interactive experiences.

## Key Artifact Types

The interaction system recognizes several core artifact types, each tailored for a specific purpose:

- **Code Artifacts**: For displaying, executing, and iterating on programming code.
- **Data Artifacts**: For visualizing datasets through charts, tables, and graphs.
- **UI Artifacts**: For rendering functional user interface components and prototypes.
- **Document Artifacts**: For structured documents, reports, and formatted text.
- **Creative Artifacts**: For non-textual creative outputs like SVG graphics and diagrams.

## Artifact Benefits

- **Clarification**: Complex ideas can be visually represented to improve understanding.
- **Interactivity**: Users can interact with the outputs (e.g., manipulate charts, run code).
- **Efficiency**: Standardized formats speed up information retrieval and task completion.
- **Context Preservation**: Artifacts maintain the relationship between the conversation and the specific technical or creative result.

## Usage Guidelines

- **Contextual Generation**: Generate artifacts only when they provide clear value over plain text.
- **Standardized Schema**: Follow the established JSON or Markdown schemas for each artifact type to ensure proper rendering.
- **Self-Dependency**: Each artifact should be self-contained and clear without excessive conversational reference.
- **Iteration Friendly**: Design artifacts so they can be easily updated or refined through follow-up prompts.

## Developer Integration

Refer to the internal Gemini Interaction protocols for detailed schema definitions and rendering engine implementation details.
