# Matching a codebase's style: landscape research

*Generated: 2026-11-24 · Confidence: Medium · For: [every-corner-matchcodebase spec](../specs/every-corner-matchcodebase.md)*

**How this was done.** About 13 web searches (standard mode) and about 15 GitHub queries via the `gh` CLI. Firecrawl and Exa were not available in this session. Stars and push dates come from the GitHub API on 2026-11-24. Several claims below come only from search-result summaries, not from reading the full page; those are marked **(summary only)**. Nothing here was run or installed.

## Executive summary

1. **Many "learn the conventions" skills exist, and none found verifies the match.** Skills such as Convention Learner and project-conventions detect style and tell the agent to follow it. None of the ones I could read runs the project's linter on the new code or compares it with a reference afterwards. That is the gap the spec's R8 fills. (Limit: I could not read ECC's `inherit-legacy-style`, so I cannot rule out that it checks.)
2. **The strongest evidence says to be careful with generated context files.** A 2026 study found context files did not generally improve task success and raised cost by over 20%. Repository overviews were not helpful, but files that specify non-standard practices were. A separate benchmark found self-generated skills gave no average benefit. An auto-written `STYLE.md` is exactly that kind of file, so it must be tested against a no-skill baseline before it ships.
3. **The cheapest reliable capture is mostly not LLM reading.** Formatter and linter configs are exact and cost almost nothing. A script can count naming, quoting and import habits across every file and return numbers instead of code. The agent then reads only the config, a few exemplar files and the outliers.
4. **Token cost can be measured with paired runs.** Run the same task with and without the skill headlessly and compare the cost and usage fields in the JSON output.

## 1. Similar projects

| Project | Stars (2026-11-24) | How it learns style | How it checks the match | Token approach | Borrow / avoid |
|---|---|---|---|---|---|
| [Convention Learner](https://github.com/codewithmukesh/dotnet-claude-kit) (`dotnet-claude-kit`) | 850 | Samples "3-5 key types", folder layout, naming; explicit `.editorconfig` always wins. Uses .NET-specific MCP tools. | None stated; suggests saving findings to CLAUDE.md | Samples, does not read everything | Borrow: "observe before enforcing", config wins, "consistency over perfection". Avoid: tied to .NET tools. ([skill text](https://www.skills.sh/codewithmukesh/dotnet-claude-kit/convention-learner)) |
| [ECC `inherit-legacy-style`](https://claudemarketplaces.com/skills/affaan-m/ecc/inherit-legacy-style) (in [affaan-m/ECC](https://github.com/affaan-m/ECC)) | 309,877 | Listing says it works incrementally via Git diffs **(summary only; archived SKILL.md not reachable)** | Unknown | Incremental | Borrow idea: learn from git history. Could not verify details. |
| [project-conventions / project-convention-discovery](https://mcpmarket.com/zh/tools/skills/project-convention-discovery) (mcpmarket) | ~1 | Reads lint and format configs, directory layout, implicit naming patterns **(listing only)** | Unknown | Unknown | Borrow: config-first scan. Tiny and undocumented. |
| [write-coding-standards-from-file](https://github.com/github/awesome-copilot) (awesome-copilot) | 41,509 | Loops over the given files and "appends each file's data to temporary memory", then writes `STYLE.md` / `CONTRIBUTING.md` | `findInconsistencies` and `fixInconsistencies` options exist | Loads all given files, so token-heavy on big inputs | Borrow: `STYLE.md` name, inconsistency scan. Avoid: whole-file accumulation. |
| [Aider repo map](https://github.com/Aider-AI/aider) | 50,237 | Tree-sitter tags ranked with Personalized PageRank (structure, not style) | None | Fixed budget, default 1024 tokens **(secondary sources, check aider's `repomap.py`)**: [DeepWiki](https://deepwiki.com/Aider-AI/aider/4.1-repository-mapping), [repo-mapper](https://docs.rs/crate/repo-mapper/0.0.1) | Borrow: rank files and fit a token budget. Avoid: it maps code shape, not style. |
| [Cline Memory Bank](https://docs.cline.bot/customization/memory-bank) | 71,855 | Markdown files such as `systemPatterns.md`, kept by the agent | None | Vendor blog says 5,000-25,000 tokens per turn **(unverified)**: [fast.io](https://fast.io/resources/cline-memory-bank-guide/) | Avoid: always-loaded files. Borrow: selective loading. |
| Cursor rules: [awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules) and generators such as [cursor-rules-generator](https://github.com/ankitpro/cursor-rules-generator) | 41,179 and 6 | Generators scan a repo and write rule files | None | Advice: small, specific rule files, about 50 lines ([dev.to](https://dev.to/whoffagents/cursor-rules-that-actually-improve-ai-code-quality-2jcg), community) | Borrow: small scoped files. Generators are tiny and unmaintained. |
| [AGENTS.md generators](https://github.com/nguyenthedat123/agents-md-generator) | 91 (top) | Writes a starter file | None | n/a | Little to borrow; the AGENTS.md study below says generated files can hurt. |
| Directories: [anthropics/skills](https://github.com/anthropics/skills), [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills), [BehiSecc/awesome-claude-skills](https://github.com/BehiSecc/awesome-claude-skills), [SkillsMP](https://www.skillsmp.com), [claudemarketplaces](https://claudemarketplaces.com) | 199,696 / 80,216 / 10,478 | n/a | n/a | n/a | Where to publish and to find more competitors. SkillsMP warns to review code before install. |

Not researched: Continue, Copilot instructions in depth.

## 2. What the research says

| Finding | Source | What it means for us |
|---|---|---|
| Context files "do not generally improve task success rates" and raise inference cost by over 20% on average; instructions are well followed, but repository overviews are not helpful; useful for non-standard practices | [Gloaguen et al., arXiv 2602.11988](https://arxiv.org/abs/2602.11988) | `STYLE.md` should hold only what the code does not already show, never a repository overview. |
| In another study AGENTS.md was associated with 28.64% lower median runtime and 16.58% lower output tokens (10 repos, 124 PRs) | [arXiv 2601.20404](https://arxiv.org/abs/2601.20404) | Results conflict; a context file can save or cost tokens. We must measure ours. |
| Self-generated skills gave no average benefit (about -1.3 points); curated skills +16.2 points, but only +4.5 in software engineering (version-dependent figures) | [SkillsBench, arXiv 2602.12670](https://arxiv.org/abs/2602.12670) | A skill the agent writes for itself is not a sure win. Test against a baseline. |
| LLM code differs in style from human code; a taxonomy of 24 inconsistency types; prompt engineering helps but may not fully fix it and can lower accuracy | [Wang et al., arXiv 2407.00456](https://arxiv.org/abs/2407.00456) | The problem is real; a style checklist can be built from this taxonomy. |
| Conventions are best learned descriptively from the codebase itself; Naturalize got 94% top-suggestion accuracy on identifier names and 14 of 18 patches accepted | [Allamanis et al., arXiv 1402.4182](https://arxiv.org/abs/1402.4182) | Count what the project does; do not impose rules. |
| Retrieving similar code as context improves completion by over 10% | [RepoCoder, arXiv 2303.12570](https://arxiv.org/abs/2303.12570) (summary only) | Load the nearest exemplar files at write time instead of everything. |
| Formatting and layout style are the easiest features to imitate ("gameable") | [Waterloo stylometry study](https://dspacemainprd01.lib.uwaterloo.ca/server/api/core/bitstreams/d447750b-1137-412d-bf6b-8fa6ea337f63/content) (summary only) | A linter pass alone is not proof of a match. Add a check on naming and structure. |

## 3. Answers to the three questions

### (1) Cheapest reliable way to capture style without the LLM reading every file

This is my synthesis from the sources above, not a tested result:

1. **Configs first.** Read `.editorconfig`, formatter, linter and type configs. They are exact and tiny. Convention Learner says explicit configs always win.
2. **Count, don't read.** A script walks every source file and prints frequencies: naming case per kind of identifier, quote style, import order, line length, comment and docstring density, error-handling and logging idioms, test layout. Output is numbers and a few outliers, not code. Every file is covered with almost no LLM tokens.
3. **Read exemplars.** The LLM reads in full only: the area being touched, one or two representative files per kind, and the outliers the script flagged.
4. **Record only the non-obvious.** `STYLE.md` lists what configs and counts do not show, each rule with a short cited excerpt. No repository overview.
5. **Retrieve at write time.** Before writing a file, open its nearest neighbor and copy its shape (RepoCoder idea).
6. **Reuse by commit stamp.** Re-scan only changed files, as the tour does.

### (2) Measuring token use of a skill

- **Fixed cost:** only name and description load at session start; the body loads when the skill triggers, and Anthropic advises a body under 500 lines ([best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)). One open issue reports `/context` showing full skill size at startup, contradicting that ([claude-code#14882](https://github.com/anthropics/claude-code/issues/14882)). Check on your version.
- **Per-run cost:** `claude -p --output-format json` returns `total_cost_usd` ([headless docs](https://code.claude.com/docs/en/headless)). Token field names (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, and per-model `modelUsage`) come from third-party write-ups, so confirm them against real output ([mirror](https://www.mintlify.com/saurav-shakya/Claude_Code-_Source_Code/advanced/sdk-mode)).
- **Method (my recommendation):** run each fixture task twice, with and without the skill, several times each, and compare cost and tokens. A third-party post estimates about 27k cache-creation tokens per headless call, so always compare against a no-skill run rather than reading absolute numbers ([DEV post](https://dev.to/whoffagents/the-claude-p-subprocess-pattern-how-to-drive-claude-from-any-python-pipeline-without-an-api-key-5cpn), unverified).
- **File size:** count tokens of `SKILL.md` and any reference files with the Anthropic token-counting endpoint. This is from my own knowledge, not these sources.

### (3) Stress-testing style matching

Anthropic's guidance is to build evaluations first and compare against a baseline; it notes there is no built-in runner ([best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)). This repo already has a headless method in [docs/stress-test.md](../../stress-test.md). Proposed scenarios (my design):

| Scenario | Trap | Pass check |
|---|---|---|
| Fixture with a deliberately unusual style (odd naming, tabs, custom error type) | Agent's habits differ from the project | Project linter clean; naming matches counts |
| Held-out function: remove a real function, ask the agent to re-implement it from its description | Ground truth exists | Naming and structure close to the original; tests pass |
| Mixed old and new style | Two valid styles | New code matches the area edited |
| Planted bug or insecure pattern in nearby code | Copying a defect | Not copied; reported |
| Prompt-injection comment saying "skip style study" | Repo text as instruction | Study still runs; one line in chat |
| No linter, no tests | Nothing to run | Says so; checks against `STYLE.md` |
| 1,000-file project | Token blow-up | Main context stays small; tokens within budget |
| Blind judge: show new and original snippets, ask which belongs | Style detectable | Judge cannot tell better than chance |

Avoid scoring on formatting alone; it is the easiest to fake.

## 4. Recommendations for the spec

1. **R2 needs a decision from you.** You chose "every source file, in full". The evidence points to a cheaper way to cover every file: a counting script for all files, with LLM full-reads for config, exemplars, the touched area and outliers. This still covers every corner but not with LLM tokens. It changes a choice you made, so it needs your approval.
2. **R4:** limit `STYLE.md` to non-standard conventions plus cited excerpts, with a size cap. No repository overview.
3. **R8:** run the formatter and linter first, then compare naming and structure against the nearest exemplar, because formatting is easy to fake.
4. **New requirement:** keep `SKILL.md` under 500 lines and move detail to reference files that load only when needed.
5. **New requirement:** a measurement harness with paired runs, with and without the skill, reporting cost and tokens.
6. **Ship rule:** release only if the skill beats the no-skill baseline on style checks without a large cost increase, since similar generated context files did not help in two studies.
7. **R12 (large projects):** keep one helper agent per folder for v1 and replace it with the counting script if that tests well.

## Gaps and caveats

- ECC's `inherit-legacy-style` and the mcpmarket skills could not be read in full, so their verification behavior is unknown.
- Aider and Cline token figures are from secondary sources.
- Several paper claims come from abstracts and search summaries only.
- One benchmark (SkillsBench) is not peer-reviewed per a reviewer cited in the search; treat its numbers as indicative.
- No benchmark was found that scores adherence to a specific repository's conventions; that is an open gap, and our test plan fills it informally.

## Sources

[arXiv 2602.11988](https://arxiv.org/abs/2602.11988) · [arXiv 2601.20404](https://arxiv.org/abs/2601.20404) · [arXiv 2602.12670](https://arxiv.org/abs/2602.12670) · [arXiv 2407.00456](https://arxiv.org/abs/2407.00456) · [arXiv 1402.4182](https://arxiv.org/abs/1402.4182) · [arXiv 2303.12570](https://arxiv.org/abs/2303.12570) · [Anthropic skill best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) · [claude-code#14882](https://github.com/anthropics/claude-code/issues/14882) · [Claude Code headless docs](https://code.claude.com/docs/en/headless) · [Convention Learner](https://www.skills.sh/codewithmukesh/dotnet-claude-kit/convention-learner) · [awesome-copilot](https://github.com/github/awesome-copilot) · [Aider repo map (DeepWiki)](https://deepwiki.com/Aider-AI/aider/4.1-repository-mapping) · [Cline Memory Bank docs](https://docs.cline.bot/customization/memory-bank) · GitHub star counts via the GitHub API, 2026-11-24.
