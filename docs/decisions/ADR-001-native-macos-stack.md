# ADR-001: Native macOS Stack

- Status: Accepted
- Date: 2026-08-24

## Context

WTM needs native file access, Finder integration, macOS permission UX, accessibility,
menu-bar integration, code signing, and long-term compatibility with Apple platform rules.

## Decision

Use Swift 6 with strict concurrency, SwiftUI for the application shell, and AppKit only
where SwiftUI does not expose the required macOS behaviour. Keep a thin Xcode app target
and one local Swift package with inward-only dependencies.

## Consequences

- Native controls, system terminology, keyboard behaviour, and accessibility are defaults.
- AppKit bridges must be small, isolated, and covered by app-level tests.
- Cross-platform UI frameworks and embedded web runtimes are outside the baseline.
- Swift API Design Guidelines and repository-wide `swift-format` are release gates.

## Requirements impact

Requirements must describe macOS-native behaviour and accessibility outcomes without
coupling ordinary feature logic to SwiftUI view types.

## Validation

Swift 6 release builds, strict formatting, package tests, app tests, and accessibility UI
smoke tests run through repository scripts and CI.
