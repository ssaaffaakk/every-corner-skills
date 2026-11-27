---
name: verify-trigger-3
description: Should invoke every-corner-verify.
tags: [verify, should-trigger]
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

We have a changed codebase and a spec under docs/every-corner/specs/. Prove the changes meet its done checks.
