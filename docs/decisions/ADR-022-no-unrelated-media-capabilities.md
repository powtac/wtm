# ADR-022: No Unrelated Media Capabilities

- Status: Accepted
- Date: 2026-08-24

## Context

LLM tools can involve speech or media, but WTM Phase 1 inventories model files. Microphone,
audio capture/playback, Media Library, Apple Music, and speech recognition are unrelated
trust boundaries and can trigger alarming permission prompts.

## Decision

Do not link media frameworks, declare media usage descriptions, request related
entitlements, or prompt for media access unless a future user-visible feature is separately
approved through an ADR and threat-model update. Audio model files, if later inventoried,
remain ordinary read-only files and do not justify device or library access.

## Consequences

- First-run copy can state that WTM does not access microphone or media libraries.
- Accidental framework imports or Xcode capability changes fail the architecture gate.
- A future audio feature must identify its exact asset, permission, data flow, storage, and
  opt-in UX rather than inheriting broad access from the inventory feature.

## Requirements impact

Security requirements must explicitly exclude unrelated permission domains and require a
new decision before expanding them.

## Validation

The architecture script scans source, configuration, and the project file for media
frameworks, usage descriptions, and entitlements; first-run tests verify the product copy.
