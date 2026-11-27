---
name: debug-trigger-2
description: Should invoke every-corner-debug.
tags: [debug, should-trigger]
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

This endpoint returns 500 only for an empty cart. Debug it and show what reproduces it before changing code.
