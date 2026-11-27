---
name: review-trigger-3
description: Should invoke every-corner-review.
tags: [review, should-trigger]
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

Perform a read-only code review of the changes before merge, including unchanged callers and tests.
