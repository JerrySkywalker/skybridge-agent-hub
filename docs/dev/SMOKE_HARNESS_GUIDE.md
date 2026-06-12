# Smoke Harness Guide

Goal 214 adds focused smoke wrappers for the shared core engine layer.

## Required Pattern

Smoke scripts should:

- use fixture modes when checking launchers, resource gates, registries, or finalizers;
- assert `token_printed=false`;
- avoid apply commands and worker execution;
- produce compact JSON;
- skip parameterized harnesses unless a wrapper provides safe arguments.

## Core Engine Smokes

The core module smokes cover module imports, safe JSON, token contract, Codex launcher fixtures, resource gate fixtures, completed-run registry reads, evidence hashes, PR path allowlists, finalizer preview-only behavior, and queue apply-disabled policy.

Wrapper compatibility smokes call only read-only/status commands for managed-mode run, managed-mode pilot, BOINC v1 preview, and local resource policy.

Desktop and Web smokes verify that the Core Engine panels expose read-only status and no execution controls.
