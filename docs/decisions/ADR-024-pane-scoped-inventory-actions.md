# ADR-024: Pane-Scoped Inventory Actions and Truthful Empty States

- Status: Accepted
- Date: 2026-08-24

## Context

WTM uses a three-column macOS `NavigationSplitView`: the sidebar selects an inventory
scope, the content pane presents the resulting collection, and the detail pane represents
the current model selection. A single global toolbar previously mixed collection actions
(`Scan`, `Filter`) with the destructive selection action (`Review Cleanup`). This obscured
which data each control affected and made an enabled Trash button appear broader than its
actual selection scope.

The content pane also used `No Models Found` whenever the visible collection was empty.
That statement was false when the ephemeral inventory contained models but the selected
sidebar scope, search text, or filter combination matched none. Offering another scan in
that state suggested the wrong recovery action.

Settings is an application-level destination, not an inventory scope. Placing it among the
selectable sidebar rows would incorrectly imply that it filters or replaces the inventory
content pane.

## Decision

Action placement follows the data scope represented by each split-view pane:

- the sidebar selects the inventory scope;
- the content-pane header owns `Scan`/`Rescan`, `Cancel Scan`, and `Filters`, while native
  search remains bound to the same collection;
- the detail pane owns model-selection actions, including the only visible Cleanup/Trash
  button. Batch selection is still represented in that pane;
- `Settings…` is pinned below the scrollable sidebar scope list in a visually separated
  footer. It opens the native SwiftUI Settings scene and does not participate in sidebar
  selection; the standard application menu command and `Command-,` remain equivalent;
- `Command-R` invokes the collection scan. `Command-Delete` is available only through an
  actionable selection context in the detail pane.

Empty presentation is derived from both the complete in-session inventory and the visible
subset:

1. no inventory while scanning: show scanning state and progress;
2. no inventory after scanning or with launch scanning disabled: show `No Models Found`
   and a scan action;
3. inventory exists but the visible subset is empty: show `No Models Match This View`,
   explain that sidebar selection, search, and filters narrow the list, and offer
   `Show All Models`;
4. `Show All Models` atomically selects `All Models`, clears search, and clears all
   content filters. It does not scan or mutate model storage.

The list header and detail controls use native SwiftUI controls, system symbols, text
labels, keyboard focus, and accessibility identifiers. Color or icon fill may reinforce an
active filter but is never its sole accessible meaning.

## Consequences

- Collection and selection actions no longer compete in one toolbar.
- A zero-result filter state cannot falsely claim that the local inventory is empty.
- The recovery action changes view scope instead of performing unnecessary filesystem IO.
- Destructive action availability is visually and semantically bound to selected models.
- Application configuration remains reachable from the collapsible navigation area without
  masquerading as an inventory filter.
- Future list-wide actions belong in the content header; future model-specific actions
  belong in the detail pane or an explicit row context.

## Requirements impact

This decision revises `FR-INV-020` and `FR-INV-021`, adds `FR-INV-028`, `FR-DEL-012`, and
`FR-EXT-015`, and refines the macOS navigation, accessibility, automated-test, and
manual-gate sections.
It does not change scan scope, source consent, deletion planning, or storage mutation
semantics.

## Validation

View-model tests distinguish no-inventory and no-match states and verify that
`Show All Models` clears sidebar, search, and structured filters. A macOS UI test selects a
sidebar scope with zero matches, verifies the truthful message and recovery action, returns
to the populated inventory, and then confirms that Cleanup remains reachable from the
selected model's detail pane. The same UI flow verifies that the sidebar footer opens the
native Settings scene. Release builds continue to compile with Swift 6 warnings as errors
and the English localization catalog gate.
