# ADR-009: Capability-Separated Adapter Roles

- Status: Accepted
- Date: 2026-08-24

## Context

External products have overlapping but non-equivalent roles. Ollama stores and runs
models, Hugging Face stores artifacts, llama.cpp runs GGUF, and OpenClaw consumes an
endpoint. One universal tool adapter would mix permissions and lifecycle semantics.

## Decision

Define separate contracts for storage inventory, storage actions, runtimes, and clients.
A product may implement multiple contracts in separate targets, but each capability is
registered and authorized independently.

## Consequences

- Read-only discovery cannot accidentally expose deletion or process APIs.
- UI behaviour is driven by capabilities rather than product-name switches.
- Provider-specific semantics stay in concrete adapter targets.
- Shared domain values remain independent from SwiftUI and concrete providers.

## Requirements impact

Every integration requirement must state adapter role, target phase, allowed operations,
evidence, permission boundary, and failure semantics.

## Validation

Phase 1 links only storage contracts and storage adapters. Package and architecture checks
reject action, runtime, and client types in the shipped graph.
