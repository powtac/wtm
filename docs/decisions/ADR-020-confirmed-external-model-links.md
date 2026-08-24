# ADR-020: Confirmed External Model Links

- Status: Accepted
- Date: 2026-08-24
- Implementation: Complete in Phase 1

## Context

A model filename or ownerless cache directory does not identify a unique upstream
repository. A non-standard local Hugging Face cache used `models--gpt-oss-20b`, which
initially produced the broken URL `https://huggingface.co/gpt-oss-20b`; the canonical
repository is `openai/gpt-oss-20b`.

## Decision

Create a confirmed external model link only from a provider-confirmed canonical repository
ID or an explicit, reviewed data alias. Hugging Face IDs must have exactly `owner/model`
components. Standard `models--owner--model` cache keys are direct evidence; ownerless keys
require an exact alias such as `gpt-oss-20b -> openai/gpt-oss-20b`. Unknown short names do
not produce a model-card link. Links use HTTPS and open only after user action.

## Consequences

- WTM prefers no link over a plausible but incorrect link.
- Aliases are versioned data with fixtures, provenance, collision review, and exact-match
  semantics; they are not fuzzy matching.
- Network search is not silently used to upgrade confidence during a local scan.
- Link confidence proves the repository mapping, not model integrity or compatibility.

## Requirements impact

Link requirements must define canonical provider IDs, accepted evidence, alias ownership,
normalization, ambiguity/collision handling, HTTPS validation, user action, offline
behaviour, and the difference between confirmed and heuristic candidates.

## Validation

Adapter contracts cover standard keys, the reviewed GPT-OSS alias, malformed components,
unknown ownerless keys, the real local Hugging Face cache, case-normalized alias collisions,
invalid local keys, and invalid canonical repository IDs. Alias catalog construction throws
before scanning when any entry is invalid.
