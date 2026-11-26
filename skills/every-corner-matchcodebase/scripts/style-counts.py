#!/usr/bin/env python3
"""Count the style habits of a project in one pass.

Prints numbers and file names, never code, so it costs almost no tokens.
Standard library only (Python 3.8+). Usage:

    python3 style-counts.py [PROJECT_ROOT] [--since COMMIT] [--outliers N] [--json]
"""
import argparse
import collections
import json
import os
import re
import stat
import subprocess
import sys
import time

# Keep the extensions in sync with hooks/require-style-study.sh.
LANGS = {
    ".py": "python", ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript",
    ".cjs": "javascript", ".ts": "typescript", ".tsx": "typescript", ".go": "go",
    ".rs": "rust", ".java": "java", ".kt": "kotlin", ".rb": "ruby", ".php": "php",
    ".c": "c", ".h": "c", ".cpp": "cpp", ".cc": "cpp", ".hpp": "cpp", ".cs": "csharp",
    ".swift": "swift", ".sh": "shell", ".scala": "scala", ".dart": "dart", ".lua": "lua",
}
SKIP_DIRS = {
    ".git", "node_modules", "vendor", "third_party", "dist", "build", "out", "target",
    "__pycache__", ".venv", "venv", ".tox", ".next", ".nuxt", "coverage", ".idea",
    ".gradle", "Pods", "bin", "obj", "site-packages", ".mypy_cache", ".pytest_cache",
}
SKIP_NAME = re.compile(
    r"(\.min\.|\.lock$|-lock\.|package-lock|\.generated\.|_pb2|\.pb\.go$|\.d\.ts$|\.snap$)"
)
MAX_BYTES = 1000000
BUDGET_SECONDS = 30   # stop reading files after this long and say so (a hostile repository must not stall the agent)
# Pattern work (quotes, imports, declarations) backtracks badly on very long lines; real code lines are short.
MAX_DECL_LINE = 400
SHA = re.compile(r"^[0-9a-fA-F]{4,40}$")
# Never let the repository's own files configure git: a committed folder shaped
# like a bare repository would otherwise be opened and its core.fsmonitor run.
GIT = ["git", "-c", "safe.bareRepository=explicit", "-c", "core.fsmonitor=false"]

FUNC = {
    "python": r"^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)",
    "javascript": r"\bfunction\s*\*?\s*([A-Za-z_$][\w$]*)|\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[\w$]+)\s*=>",
    "go": r"^func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)",
    "rust": r"\bfn\s+([A-Za-z_]\w*)",
    "ruby": r"^\s*def\s+(?:self\.)?([A-Za-z_]\w*)",
    "php": r"\bfunction\s+([A-Za-z_]\w*)",
    "swift": r"\bfunc\s+([A-Za-z_]\w*)",
    "kotlin": r"\bfun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?([A-Za-z_]\w*)",
    "shell": r"^\s*(?:function\s+)?([A-Za-z_]\w*)\s*\(\)",
    "java": r"^\s*(?:(?:public|private|protected|static|final|abstract|synchronized)\s+)+[\w.?\[\]]+(?:<[^<>;()]*>)?(?:\[\])*\s+([a-z_]\w*)\s*\([^;]*$",
    "csharp": r"^\s*(?:(?:public|private|protected|internal|static|async|virtual|override)\s+)+[\w.?\[\]]+(?:<[^<>;()]*>)?(?:\[\])*\s+([A-Za-z_]\w*)\s*\([^;]*$",
    "dart": r"^\s*(?:static\s+)?[\w<>?]+\s+([a-z_]\w*)\s*\([^;]*\)\s*(?:async\s*)?\{",
    "scala": r"\bdef\s+([A-Za-z_]\w*)",
    "lua": r"\bfunction\s+(?:[\w.]+[.:])?([A-Za-z_]\w*)",
    "c": r"^[A-Za-z_][\w\s\*]*\s+\**([A-Za-z_]\w*)\s*\([^;]*$",
}
FUNC["typescript"] = FUNC["javascript"]
FUNC["cpp"] = FUNC["c"]
CLASS = {
    "python": r"^\s*class\s+([A-Za-z_]\w*)",
    "javascript": r"\bclass\s+([A-Za-z_$][\w$]*)",
    "typescript": r"\b(?:class|interface|enum)\s+([A-Za-z_$][\w$]*)",
    "go": r"^type\s+([A-Za-z_]\w*)\s+(?:struct|interface)",
    "rust": r"\b(?:struct|enum|trait)\s+([A-Za-z_]\w*)",
    "java": r"\b(?:class|interface|enum)\s+([A-Za-z_]\w*)",
    "kotlin": r"\b(?:class|interface|object)\s+([A-Za-z_]\w*)",
    "csharp": r"\b(?:class|interface|struct|enum)\s+([A-Za-z_]\w*)",
    "ruby": r"^\s*(?:class|module)\s+([A-Za-z_]\w*)",
    "php": r"\b(?:class|interface|trait)\s+([A-Za-z_]\w*)",
    "swift": r"\b(?:class|struct|enum|protocol)\s+([A-Za-z_]\w*)",
    "cpp": r"\b(?:class|struct)\s+([A-Za-z_]\w*)",
    "scala": r"\b(?:class|trait|object)\s+([A-Za-z_]\w*)",
    "dart": r"\bclass\s+([A-Za-z_]\w*)",
}
CONST = {
    "python": r"^([A-Z][A-Z0-9_]+)\s*(?::[^=]+)?=",
    "javascript": r"\bconst\s+([A-Z][A-Z0-9_]+)\s*=",
    "typescript": r"\bconst\s+([A-Z][A-Z0-9_]+)\s*=",
    "go": r"^\s*(?:const\s+)?([A-Z][A-Za-z0-9_]*)\s*=",
    "rust": r"\b(?:const|static)\s+([A-Z][A-Z0-9_]+)\s*:",
}
COMMENT_START = {
    "python": ("#",), "ruby": ("#",), "shell": ("#",),
    "lua": ("--",),
}
IDIOMS = {
    "python": {
        "except_Exception": r"\bexcept\s+Exception\b", "bare_except": r"\bexcept\s*:",
        "raise": r"\braise\b", "logging": r"\b(?:logging|logger|log)\.\w+\(", "print": r"(?<![\w.])print\(",
        "type_hints": r"\)\s*->\s*\w", "f_strings": r"\bf[\"']",
    },
    "javascript": {
        "try": r"\btry\s*\{", "catch_call": r"\.catch\(", "console": r"\bconsole\.\w+\(",
        "require": r"\brequire\(", "import_from": r"^[ \t]*import[ \t][^\n]+[ \t]from[ \t]", "async_await": r"\bawait\b",
        "arrow_fn": r"=>", "function_kw": r"\bfunction\b",
    },
    "go": {
        "err_check": r"if\s+err\s*!=\s*nil", "log": r"\blog\.\w+\(", "fmt_print": r"\bfmt\.Print\w*\(",
        "errors_wrap": r"%w|errors\.(?:New|Wrap|Is|As)\b",
    },
    "rust": {
        "unwrap": r"\.unwrap\(\)", "question_mark": r"\?\s*[;)\n]", "println": r"\bprintln!",
        "expect": r"\.expect\(",
    },
    "java": {
        "try": r"\btry\s*[({]", "logger": r"\b(?:log|logger|LOG)\.\w+\(", "sysout": r"System\.(?:out|err)\.",
    },
}
IDIOMS["typescript"] = IDIOMS["javascript"]
# Per-line patterns, compiled once (they run on every line of every file).
LINE_COMMENT = re.compile(r"//.*$")
DQ = re.compile(r'"(?:[^"\\]|\\.)*"')
SQ = re.compile(r"'(?:[^'\\]|\\.)*'")
ENDS_LIKE_STMT = re.compile(r"[\w)\]'\"`]$")
STMT_START = re.compile(r"(const|let|var|return|throw|await|break|continue|import|export\s+(const|default|let)"
                        r"|[\w$.\[\]]+\(|[\w$.\[\]]+\s*=[^=>])")
PY_IMPORT = re.compile(r"(from\s+(\S+)\s+import|import\s+(\S+))")
JS_IMPORT = re.compile(r"(import\s+.*?from\s+['\"](\S+)['\"]|import\s+['\"](\S+)['\"])")
BLANK_RUN = re.compile(r"\s{2,}")   # every kind of whitespace: NBSP, form feed, U+2003 too
COMPILED = {kind: {lang: re.compile(rx) for lang, rx in table.items()}
            for kind, table in (("func", FUNC), ("class", CLASS), ("const", CONST))}
# Each idiom with the literal it cannot match without; a file that lacks the
# literal skips that whole-text scan (patterns starting with \b are slow).
IDIOM_RX = {lang: [(k, re.compile(rx, re.M), re.match(r"(?:\\b)?([A-Za-z_]{3,})", rx))
                   for k, rx in table.items()] for lang, table in IDIOMS.items()}
IDIOM_RX = {lang: [(k, rx, m.group(1) if m else None) for k, rx, m in items] for lang, items in IDIOM_RX.items()}


def read_regular(path, max_bytes, errors="strict"):
    """Text of a plain file, or (None, reason). Never follows a symlink and never
    opens a named pipe: a hostile repository can contain both (outside paths, hangs)."""
    try:
        info = os.lstat(path)
        if not stat.S_ISREG(info.st_mode):
            return None, "symlink or special file"
        if info.st_size > max_bytes:
            return None, "over 1 MB"
        with open(path, "r", encoding="utf-8", errors=errors, newline="") as fh:
            return fh.read(), None
    except (OSError, UnicodeDecodeError):
        return None, "unreadable/binary"


TEST_RE = re.compile(r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]+$|_test\.\w+$|\.(test|spec)\.\w+$")
CONFIG_FILES = [
    ".editorconfig", ".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js",
    ".eslintrc", ".eslintrc.json", ".eslintrc.js", "eslint.config.js", "eslint.config.mjs",
    "biome.json", "pyproject.toml", "setup.cfg", "tox.ini", ".flake8", "ruff.toml", ".ruff.toml",
    ".pylintrc", "mypy.ini", "rustfmt.toml", ".rustfmt.toml", "clippy.toml", ".golangci.yml",
    ".golangci.yaml", ".clang-format", ".rubocop.yml", "phpcs.xml", ".php-cs-fixer.php",
    "checkstyle.xml", ".swiftlint.yml", "tsconfig.json", "Makefile", "package.json", "justfile",
    "CONTRIBUTING.md", "STYLE.md", ".pre-commit-config.yaml",
]
PY_TOOL_SECTIONS = ["tool.ruff", "tool.black", "tool.isort", "tool.mypy", "tool.pytest", "tool.flake8"]


def case_of(name):
    n = name.strip("_$")
    if len(n) < 2 or not any(c.isalpha() for c in n):
        return None
    if n.isupper():
        return "UPPER_SNAKE" if "_" in n or len(n) > 3 else None
    if "-" in n:
        return "kebab-case" if n.lower() == n else None
    if "_" in n:
        return "snake_case" if n.lower() == n else "Mixed_Snake"
    if n[0].isupper():
        return "PascalCase" if any(c.islower() for c in n) else None
    if any(c.isupper() for c in n):
        return "camelCase"
    return None  # single lowercase word: fits several cases, so it says nothing


def list_files(root, since):
    try:
        if since:
            # Against the working tree, plus untracked files: uncommitted work counts too.
            out = subprocess.run(GIT + ["-C", root, "diff", "--name-only", "-z", "--relative", since, "--"],
                                 capture_output=True, check=True).stdout.decode("utf-8", "surrogateescape")
            out += subprocess.run(GIT + ["-C", root, "ls-files", "--others", "--exclude-standard", "-z"],
                                  capture_output=True, check=True).stdout.decode("utf-8", "surrogateescape")
            files = sorted({f for f in out.split("\0") if f and os.path.exists(os.path.join(root, f))})
        else:
            out = subprocess.run(GIT + ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                                 capture_output=True, check=True).stdout.decode("utf-8", "surrogateescape")
            files = [f for f in out.split("\0") if f]
        return files, True
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        if since:
            sys.exit("style-counts.py: git could not list the files changed since %s; run without --since" % since)
        files = []
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                files.append(os.path.relpath(os.path.join(dp, fn), root))
        return files, False


def indent_unit(widths):  # widths: Counter of indent width -> number of lines
    total = sum(widths.values())
    if not total:
        return None
    for unit in (8, 4, 3, 2):
        if sum(c for w, c in widths.items() if w % unit == 0) / total >= 0.95:
            return unit
    return 1


def analyze_file(lang, text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    st = {"lines": len(lines), "tab_lines": 0, "space_widths": collections.Counter(), "dq": 0, "sq": 0, "bt": 0,
          "semi": 0, "nosemi": 0, "lens": collections.Counter(), "trail_ws": 0, "comment": 0, "docstrings": 0,
          "final_newline": text.endswith("\n"), "crlf": "\r\n" in text,
          "funcs": collections.Counter(), "classes": collections.Counter(),
          "consts": collections.Counter(), "idioms": collections.Counter(),
          "import_groups": 0, "import_groups_sorted": 0, "rel_imports": 0, "abs_imports": 0}
    cstart = COMMENT_START.get(lang, ("//", "/*", "*", "#" if lang == "php" else "//"))
    fre, cre, kre = (COMPILED[kind].get(lang) for kind in ("func", "class", "const"))
    group = []

    def flush_group():
        if len(group) > 1:
            st["import_groups"] += 1
            keys = [g.lower() for g in group]
            if keys == sorted(keys):
                st["import_groups_sorted"] += 1
        del group[:]

    for ln in lines:
        raw = ln.rstrip("\r")
        s = raw.strip()
        if not s:
            flush_group()
            continue
        if raw != raw.rstrip():
            st["trail_ws"] += 1
        st["lens"][len(raw)] += 1
        lead = raw[:len(raw) - len(raw.lstrip())]
        if lead:
            if lead[0] == "\t":
                st["tab_lines"] += 1
            else:
                st["space_widths"][len(lead)] += 1
        is_comment = s.startswith(cstart)
        if is_comment:
            st["comment"] += 1
        if len(raw) > MAX_DECL_LINE:
            # Minified or generated code: the quote, import and declaration patterns backtrack
            # badly on lines like this, so such a line counts for length and indent only.
            flush_group()
            continue
        if is_comment:
            pass
        elif lang in ("python", "ruby", "javascript", "typescript", "php"):
            code = LINE_COMMENT.sub("", s) if lang not in ("python", "ruby") else s
            st["dq"] += len(DQ.findall(code))
            st["sq"] += len(SQ.findall(code))
            if lang in ("javascript", "typescript"):
                st["bt"] += code.count("`") // 2
        if lang == "python" and (s.startswith('"""') or s.startswith("'''")):
            st["docstrings"] += 1
        if lang in ("javascript", "typescript") and not is_comment:
            if s.endswith(";"):
                st["semi"] += 1
            elif ENDS_LIKE_STMT.search(s) and STMT_START.match(s):
                st["nosemi"] += 1
        if lang == "python":
            m = PY_IMPORT.match(raw)
        elif lang in ("javascript", "typescript"):
            m = JS_IMPORT.match(raw)
        else:
            m = None
        if m:
            target = m.group(2) or m.group(3) or ""
            group.append(raw)
            if target.startswith("."):
                st["rel_imports"] += 1
            else:
                st["abs_imports"] += 1
        else:
            flush_group()
        if not is_comment:
            decl = BLANK_RUN.sub(" ", raw)  # collapse runs: the patterns only need words
            if fre:
                fm = fre.search(decl)
                if fm:
                    name = next((g for g in fm.groups() if g), None)
                    c = case_of(name) if name else None
                    if c:
                        st["funcs"][c] += 1
            if cre:
                cm = cre.search(decl)
                if cm:
                    c = case_of(cm.group(1))
                    if c:
                        st["classes"][c] += 1
            if kre:
                km = kre.search(decl)
                if km:
                    st["consts"][case_of(km.group(1)) or "UPPER_SNAKE"] += 1
    flush_group()
    for k, rx, hint in IDIOM_RX.get(lang, ()):
        if hint and hint not in text:
            continue
        n = len(rx.findall(text))
        if n:
            st["idioms"][k] += n
    return st


def dominant(counter, minimum):
    return counter.most_common(1)[0][0] if sum(counter.values()) >= minimum else None


def pct(n, total):
    return int(round(100.0 * n / total)) if total else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--since", help="only count files changed since this commit")
    ap.add_argument("--outliers", type=int, default=5, help="outliers listed per language")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    ap.add_argument("--budget", type=float, default=BUDGET_SECONDS, help="stop reading files after this many seconds")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        ap.error("%s is not a folder" % a.root)
    if a.since and not SHA.match(a.since):
        ap.error("--since must be a commit hash (4-40 hex characters), got %r" % a.since)
    if a.since and subprocess.run(GIT + ["-C", root, "rev-parse", "--verify", "--quiet", a.since + "^{commit}"],
                                  capture_output=True).returncode != 0:
        ap.error("--since %s is not a commit in this repository (stale stamp?): run without --since" % a.since)
    files, is_git = list_files(root, a.since)

    skipped = collections.Counter()
    folders = collections.Counter()
    per_lang = collections.defaultdict(list)
    started = time.monotonic()
    for n, rel in enumerate(files):
        if time.monotonic() - started >= a.budget:
            skipped["not reached (%g s time budget)" % a.budget] += len(files) - n
            break
        parts = rel.split("/")
        folders[parts[0] if len(parts) > 1 else "."] += 1
        ext = os.path.splitext(rel)[1].lower()
        if any(p in SKIP_DIRS for p in parts[:-1]):
            skipped["vendored/build dirs"] += 1
            continue
        if SKIP_NAME.search(rel):
            skipped["generated/lock/minified"] += 1
            continue
        lang = LANGS.get(ext)
        if not lang:
            skipped["not source (docs, data, media, config)"] += 1
            continue
        text, why = read_regular(os.path.join(root, rel), MAX_BYTES)
        if why:
            skipped[why] += 1
            continue
        st = analyze_file(lang, text)
        st["path"] = rel
        st["is_test"] = bool(TEST_RE.search(rel))
        stem = os.path.splitext(os.path.basename(rel))[0]
        stem = re.sub(r"\.(test|spec|config|d|stories|module)$", "", stem)
        st["is_config_file"] = bool(re.search(r"(^|[._-])config([._-]|$)|^\.", os.path.basename(rel)))
        st["is_component"] = ext in (".tsx", ".jsx")
        st["name_case"] = case_of(stem.replace(".", "_") if "-" not in stem else stem)
        per_lang[lang].append(st)

    report = {"root": root, "git": is_git, "files_listed": len(files),
              "files_counted": sum(len(v) for v in per_lang.values()),
              "skipped": dict(skipped), "folders": dict(folders.most_common()), "languages": {}}

    for lang, sts in sorted(per_lang.items(), key=lambda kv: -len(kv[1])):
        def tot(key):
            return sum(s[key] for s in sts)
        tot_lines, tab = tot("lines"), tot("tab_lines")
        widths = sum((s["space_widths"] for s in sts), collections.Counter())
        n_space = sum(widths.values())
        indented = tab + n_space
        unit = indent_unit(widths)
        dq, sq, bt = tot("dq"), tot("sq"), tot("bt")
        lens = sum((s["lens"] for s in sts), collections.Counter())
        n_lens = sum(lens.values())
        p95 = 0
        if n_lens:
            want, seen = int(0.95 * (n_lens - 1)), 0   # the same element a sorted list would give
            for length in sorted(lens):
                seen += lens[length]
                if seen > want:
                    p95 = length
                    break
        funcs, classes, consts, idioms = (sum((s[k] for s in sts), collections.Counter())
                                          for k in ("funcs", "classes", "consts", "idioms"))
        ig, igs = tot("import_groups"), tot("import_groups_sorted")
        semi, nosemi = tot("semi"), tot("nosemi")
        crlf_files = sum(1 for s in sts if s["crlf"])
        mixed_crlf = 0 < crlf_files < len(sts)
        name_cases = collections.Counter(
            s["name_case"] for s in sts if s["name_case"] and not s["is_config_file"])
        tests = [s for s in sts if s["is_test"]]
        dom_indent = "tabs" if tab > n_space else "spaces"
        dom_func = dominant(funcs, 3)
        dom_quote = ("double" if dq >= sq else "single") if (dq + sq) >= 5 else None
        dom_name = dominant(name_cases, 3)

        # outliers: files whose own habits differ from the language majority
        scored = []
        for s in sts:
            flags = []
            s_space = sum(s["space_widths"].values())
            if s["tab_lines"] + s_space >= 5:
                f_tab = s["tab_lines"] > s_space
                if f_tab != (dom_indent == "tabs"):
                    flags.append("indent " + ("tabs" if f_tab else "spaces"))
                elif not f_tab and unit and unit > 1 and s_space >= 20:
                    fu = indent_unit(s["space_widths"])
                    if fu > 1 and fu != unit:
                        flags.append("indent width %d" % fu)
            if dom_quote and s["dq"] + s["sq"] >= 5:
                fq = "double" if s["dq"] >= s["sq"] else "single"
                if fq != dom_quote:
                    flags.append("quotes " + fq)
            if dom_func and sum(s["funcs"].values()) >= 2:
                fc = s["funcs"].most_common(1)[0][0]
                habits = ("snake_case", "camelCase") if lang in ("javascript", "typescript") \
                    else ("snake_case", "camelCase", "PascalCase")
                if fc != dom_func and fc in habits and dom_func in habits:
                    flags.append("function names " + fc)
            if dom_name and s["name_case"] and s["name_case"] != dom_name \
                    and not s["is_config_file"] and not (s["is_component"] and s["name_case"] == "PascalCase"):
                flags.append("file name " + s["name_case"])
            if s["crlf"] and mixed_crlf:
                flags.append("CRLF line endings")
            if flags:
                scored.append((len(flags), s["path"], flags))
        scored.sort(key=lambda t: (-t[0], t[1]))
        flagged = {p for _, p, _ in scored}
        # examples: unflagged, non-test files closest to the median size
        pool = sorted((s for s in sts if s["path"] not in flagged and not s["is_test"]), key=lambda s: s["lines"])
        examples = []
        if pool:
            mid = len(pool) // 2
            for i in (mid, mid - 1, mid + 1):
                if 0 <= i < len(pool) and pool[i]["path"] not in examples and len(examples) < 2:
                    examples.append(pool[i]["path"])

        report["languages"][lang] = {
            "files": len(sts), "lines": tot_lines,
            "indent": {"dominant": dom_indent, "tab_pct": pct(tab, indented), "unit": unit},
            "quotes": {"double": dq, "single": sq, "backtick": bt, "dominant": dom_quote},
            "semicolons": ({"yes": semi, "no": nosemi} if lang in ("javascript", "typescript") else None),
            "line_length": {"p95": p95, "max": max(lens) if lens else 0},
            "functions": dict(funcs), "classes": dict(classes), "constants": dict(consts),
            "file_names": dict(name_cases),
            "comment_line_pct": pct(tot("comment"), tot_lines),
            "docstring_blocks": tot("docstrings"),
            "imports": {"groups": ig, "sorted_groups": igs,
                        "relative": tot("rel_imports"), "absolute": tot("abs_imports")},
            "idioms": dict(idioms),
            "trailing_whitespace_lines": tot("trail_ws"),
            "files_without_final_newline": sum(1 for s in sts if not s["final_newline"]),
            "crlf_files": crlf_files,
            "tests": {"files": len(tests), "examples": [t["path"] for t in tests[:2]]},
            "examples": examples,
            "outliers": [{"path": p, "flags": f} for _, p, f in scored[:a.outliers]],
            "outliers_total": len(scored),
        }

    # tooling
    present = [c for c in CONFIG_FILES if os.path.exists(os.path.join(root, c))]
    tools = {"configs": present, "commands": {}}
    body, _ = read_regular(os.path.join(root, "package.json"), MAX_BYTES)
    if body:
        try:
            scripts = json.loads(body).get("scripts", {})
            if not isinstance(scripts, dict):
                scripts = {}
            for k in ("lint", "format", "fmt", "test", "typecheck", "check"):
                if k in scripts:
                    tools["commands"][k] = "npm run " + k
        except (ValueError, AttributeError, TypeError, RecursionError):
            pass
    body, _ = read_regular(os.path.join(root, "pyproject.toml"), MAX_BYTES, errors="ignore")
    if body:
        found = [t for t in PY_TOOL_SECTIONS if "[" + t in body]
        if found:
            tools["configs"] = [c + ("[" + ",".join(found) + "]" if c == "pyproject.toml" else "") for c in present]
    body, _ = read_regular(os.path.join(root, "Makefile"), MAX_BYTES, errors="ignore")
    if body:
        for k in ("lint", "format", "fmt", "test", "check"):
            if re.search(r"^%s\s*:" % k, body, re.M):
                tools["commands"].setdefault(k, "make " + k)
    report["tooling"] = tools

    if a.json:
        print(json.dumps(report, indent=1, sort_keys=True))
    else:
        print_text(report)
    return 0


def mix(counter):
    counter = collections.Counter(counter)
    total = sum(counter.values())
    if not total:
        return "none found"
    return ", ".join("%s %d%%" % (k, pct(v, total)) for k, v in counter.most_common(3)) + " (n=%d)" % total


def clean(text):
    """A file name from the repository, safe to print: control characters (a newline or an
    ANSI escape would forge output lines) and bytes that are not UTF-8 are shown escaped."""
    return "".join(c if c.isprintable() else ("\\x%02x" % ord(c) if ord(c) < 256 else "\\u%04x" % ord(c))
                   for c in text)


def print_text(r):
    sk = sum(r["skipped"].values())
    print("STYLE COUNTS  root=%s  git=%s" % (clean(r["root"]), r["git"]))
    print("files listed %d | counted %d | skipped %d %s" % (
        r["files_listed"], r["files_counted"], sk, dict(r["skipped"]) if sk else ""))
    print("folders: " + ", ".join("%s %d" % (clean(k), v) for k, v in list(r["folders"].items())[:15]))
    for lang, d in r["languages"].items():
        print("\n== %s (%d files, %d lines)" % (lang, d["files"], d["lines"]))
        ind = d["indent"]
        print("indent: %s%s (%d%% of indented lines use tabs)" % (
            ind["dominant"], (" x%d" % ind["unit"]) if ind["dominant"] == "spaces" and ind["unit"] else "", ind["tab_pct"]))
        q = d["quotes"]
        if q["dominant"]:
            print("quotes: double %d, single %d%s -> %s" % (
                q["double"], q["single"], (", backtick %d" % q["backtick"]) if q["backtick"] else "", q["dominant"]))
        if d["semicolons"]:
            s = d["semicolons"]
            tot = s["yes"] + s["no"]
            print("semicolons: %s (%d with, %d without; approximate)" % (
                "yes" if pct(s["yes"], tot) >= 80 else "no" if pct(s["yes"], tot) <= 20 else "mixed", s["yes"], s["no"]))
        print("line length: p95 %d, max %d" % (d["line_length"]["p95"], d["line_length"]["max"]))
        print("functions: " + mix(d["functions"]))
        if d["classes"]:
            print("classes: " + mix(d["classes"]))
        if d["constants"]:
            print("constants: " + mix(d["constants"]))
        print("file names: " + mix(d["file_names"]))
        extra = "comments %d%% of lines" % d["comment_line_pct"]
        if d["docstring_blocks"]:
            extra += ", docstring blocks %d" % d["docstring_blocks"]
        print(extra)
        im = d["imports"]
        if im["groups"] or im["relative"] or im["absolute"]:
            print("imports: %d/%d multi-line groups sorted; relative %d, absolute %d" % (
                im["sorted_groups"], im["groups"], im["relative"], im["absolute"]))
        if d["idioms"]:
            print("idioms: " + ", ".join("%s %d" % kv for kv in sorted(d["idioms"].items())))
        hygiene = []
        if d["trailing_whitespace_lines"]:
            hygiene.append("trailing whitespace on %d lines" % d["trailing_whitespace_lines"])
        if d["files_without_final_newline"]:
            hygiene.append("%d files lack a final newline" % d["files_without_final_newline"])
        if d["crlf_files"]:
            hygiene.append("%d files use CRLF" % d["crlf_files"])
        if hygiene:
            print("hygiene: " + "; ".join(hygiene))
        t = d["tests"]
        print("tests: %d files%s" % (t["files"], (" e.g. " + ", ".join(clean(e) for e in t["examples"])) if t["examples"] else ""))
        if d["examples"]:
            print("examples (read in full): " + ", ".join(clean(e) for e in d["examples"]))
        if d["outliers"]:
            print("outliers (read in full) %d total, showing %d:" % (d["outliers_total"], len(d["outliers"])))
            for o in d["outliers"]:
                print("  %s  [%s]" % (clean(o["path"]), "; ".join(o["flags"])))
        else:
            print("outliers: none")
    t = r["tooling"]
    print("\n== tooling")
    print("configs: " + (", ".join(t["configs"]) if t["configs"] else "none found"))
    print("commands: " + (", ".join("%s=%s" % kv for kv in t["commands"].items()) if t["commands"] else "none found"))


if __name__ == "__main__":
    sys.exit(main())
