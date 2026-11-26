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
# Declaration patterns backtrack badly on very long lines; real declarations are short.
MAX_DECL_LINE = 400
SHA = re.compile(r"^[0-9a-fA-F]{4,40}$")

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
    "java": r"^\s*(?:public|private|protected|static|final|abstract|synchronized|\s)+[\w<>\[\],.? ]+\s+([a-z_]\w*)\s*\([^;]*$",
    "csharp": r"^\s*(?:public|private|protected|internal|static|async|virtual|override|\s)+[\w<>\[\],.? ]+\s+([A-Za-z_]\w*)\s*\([^;]*$",
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
        "require": r"\brequire\(", "import_from": r"^\s*import\s.+\sfrom\s", "async_await": r"\bawait\b",
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
            out = subprocess.run(["git", "-C", root, "diff", "--name-only", since + "..HEAD"],
                                 capture_output=True, text=True, check=True).stdout
            files = [f for f in out.splitlines() if os.path.exists(os.path.join(root, f))]
        else:
            out = subprocess.run(["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                                 capture_output=True, text=True, check=True).stdout
            files = [f for f in out.split("\0") if f]
        return files, True
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        files = []
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                files.append(os.path.relpath(os.path.join(dp, fn), root))
        return files, False


def indent_unit(widths):
    if not widths:
        return None
    total = len(widths)
    for unit in (8, 4, 3, 2):
        if sum(1 for w in widths if w % unit == 0) / total >= 0.95:
            return unit
    return 1


def analyze_file(path, lang, text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    st = {"lines": len(lines), "tab_lines": 0, "space_widths": [], "dq": 0, "sq": 0, "bt": 0,
          "semi": 0, "nosemi": 0, "lens": [], "trail_ws": 0, "comment": 0, "docstrings": 0,
          "final_newline": text.endswith("\n"), "crlf": "\r\n" in text,
          "funcs": collections.Counter(), "classes": collections.Counter(),
          "consts": collections.Counter(), "idioms": collections.Counter(),
          "import_groups": 0, "import_groups_sorted": 0, "rel_imports": 0, "abs_imports": 0}
    cstart = COMMENT_START.get(lang, ("//", "/*", "*", "#" if lang == "php" else "//"))
    fre = re.compile(FUNC[lang]) if lang in FUNC else None
    cre = re.compile(CLASS[lang]) if lang in CLASS else None
    kre = re.compile(CONST[lang]) if lang in CONST else None
    idi = {k: re.compile(v, re.M) for k, v in IDIOMS.get(lang, {}).items()}
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
        st["lens"].append(len(raw))
        lead = raw[:len(raw) - len(raw.lstrip())]
        if lead:
            if lead[0] == "\t":
                st["tab_lines"] += 1
            else:
                st["space_widths"].append(len(lead))
        is_comment = s.startswith(cstart)
        if is_comment:
            st["comment"] += 1
        elif lang in ("python", "ruby", "javascript", "typescript", "php"):
            code = re.sub(r"//.*$", "", s) if lang != "python" and lang != "ruby" else s
            st["dq"] += len(re.findall(r'"(?:[^"\\]|\\.)*"', code))
            st["sq"] += len(re.findall(r"'(?:[^'\\]|\\.)*'", code))
            if lang in ("javascript", "typescript"):
                st["bt"] += code.count("`") // 2
        if lang == "python" and (s.startswith('"""') or s.startswith("'''")):
            st["docstrings"] += 1
        if lang in ("javascript", "typescript") and not is_comment:
            if s.endswith(";"):
                st["semi"] += 1
            elif re.search(r"[\w)\]'\"`]$", s) and re.match(
                    r"(const|let|var|return|throw|await|break|continue|import|export\s+(const|default|let)"
                    r"|[\w$.\[\]]+\(|[\w$.\[\]]+\s*=[^=>])", s):
                st["nosemi"] += 1
        if lang == "python":
            m = re.match(r"(from\s+(\S+)\s+import|import\s+(\S+))", raw)
        elif lang in ("javascript", "typescript"):
            m = re.match(r"(import\s+.*?from\s+['\"](\S+)['\"]|import\s+['\"](\S+)['\"])", raw)
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
        if not is_comment and len(raw) <= MAX_DECL_LINE:
            raw = re.sub(r"[ \t]{2,}", " ", raw)  # collapse runs: the patterns only need words
            if fre:
                fm = fre.search(raw)
                if fm:
                    name = next((g for g in fm.groups() if g), None)
                    c = case_of(name) if name else None
                    if c:
                        st["funcs"][c] += 1
            if cre:
                cm = cre.search(raw)
                if cm:
                    c = case_of(cm.group(1))
                    if c:
                        st["classes"][c] += 1
            if kre:
                km = kre.search(raw)
                if km:
                    st["consts"][case_of(km.group(1)) or "UPPER_SNAKE"] += 1
    flush_group()
    for k, rx in idi.items():
        n = len(rx.findall(text))
        if n:
            st["idioms"][k] += n
    return st


def dominant(counter, minimum=1):
    total = sum(counter.values())
    if total < minimum:
        return None
    name, n = counter.most_common(1)[0]
    return name


def pct(n, total):
    return int(round(100.0 * n / total)) if total else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--since", help="only count files changed since this commit")
    ap.add_argument("--outliers", type=int, default=5, help="outliers listed per language")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    if a.since and not SHA.match(a.since):
        ap.error("--since must be a commit hash (4-40 hex characters), got %r" % a.since)
    files, is_git = list_files(root, a.since)

    skipped = collections.Counter()
    folders = collections.Counter()
    per_lang = collections.defaultdict(list)
    for rel in files:
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
        full = os.path.join(root, rel)
        try:
            # Only plain files: a symlink or a named pipe could point outside the
            # project or block forever (a hostile repository can contain both).
            info = os.lstat(full)
            if not stat.S_ISREG(info.st_mode):
                skipped["symlink or special file"] += 1
                continue
            if info.st_size > MAX_BYTES:
                skipped["over 1 MB"] += 1
                continue
            with open(full, "r", encoding="utf-8", errors="strict", newline="") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            skipped["unreadable/binary"] += 1
            continue
        st = analyze_file(rel, lang, text)
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
        tot_lines = sum(s["lines"] for s in sts)
        tab = sum(s["tab_lines"] for s in sts)
        widths = [w for s in sts for w in s["space_widths"]]
        indented = tab + len(widths)
        unit = indent_unit(widths)
        dq, sq, bt = (sum(s[k] for s in sts) for k in ("dq", "sq", "bt"))
        lens = sorted(l for s in sts for l in s["lens"])
        p95 = lens[int(0.95 * (len(lens) - 1))] if lens else 0
        funcs, classes, consts = (collections.Counter() for _ in range(3))
        idioms = collections.Counter()
        for s in sts:
            funcs.update(s["funcs"]); classes.update(s["classes"]); consts.update(s["consts"])
            idioms.update(s["idioms"])
        ig = sum(s["import_groups"] for s in sts)
        igs = sum(s["import_groups_sorted"] for s in sts)
        semi, nosemi = sum(s["semi"] for s in sts), sum(s["nosemi"] for s in sts)
        name_cases = collections.Counter(
            s["name_case"] for s in sts if s["name_case"] and not s["is_config_file"])
        tests = [s for s in sts if s["is_test"]]
        dom_indent = "tabs" if tab > len(widths) else "spaces"
        dom_func = dominant(funcs, 3)
        dom_quote = ("double" if dq >= sq else "single") if (dq + sq) >= 5 else None
        dom_name = dominant(name_cases, 3)

        # outliers: files whose own habits differ from the language majority
        scored = []
        for s in sts:
            flags = []
            if s["tab_lines"] + len(s["space_widths"]) >= 5:
                f_tab = s["tab_lines"] > len(s["space_widths"])
                if (f_tab and dom_indent == "spaces") or (not f_tab and dom_indent == "tabs"):
                    flags.append("indent " + ("tabs" if f_tab else "spaces"))
                elif not f_tab and dom_indent == "spaces" and unit and s["space_widths"]:
                    fu = indent_unit(s["space_widths"])
                    if fu and fu > 1 and unit and unit > 1 and fu != unit and len(s["space_widths"]) >= 20:
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
            if s["crlf"] and not all(x["crlf"] for x in sts):
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
            "line_length": {"p95": p95, "max": lens[-1] if lens else 0},
            "functions": dict(funcs), "classes": dict(classes), "constants": dict(consts),
            "file_names": dict(name_cases),
            "comment_line_pct": pct(sum(s["comment"] for s in sts), tot_lines),
            "docstring_blocks": sum(s["docstrings"] for s in sts),
            "imports": {"groups": ig, "sorted_groups": igs,
                        "relative": sum(s["rel_imports"] for s in sts),
                        "absolute": sum(s["abs_imports"] for s in sts)},
            "idioms": dict(idioms),
            "trailing_whitespace_lines": sum(s["trail_ws"] for s in sts),
            "files_without_final_newline": sum(1 for s in sts if not s["final_newline"]),
            "crlf_files": sum(1 for s in sts if s["crlf"]),
            "tests": {"files": len(tests), "examples": [t["path"] for t in tests[:2]]},
            "examples": examples,
            "outliers": [{"path": p, "flags": f} for _, p, f in scored[:a.outliers]],
            "outliers_total": len(scored),
        }

    # tooling
    present = [c for c in CONFIG_FILES if os.path.exists(os.path.join(root, c))]
    tools = {"configs": present, "commands": {}}
    pj = os.path.join(root, "package.json")
    if os.path.exists(pj):
        try:
            scripts = json.load(open(pj)).get("scripts", {})
            for k in ("lint", "format", "fmt", "test", "typecheck", "check"):
                if k in scripts:
                    tools["commands"][k] = "npm run " + k
        except (ValueError, OSError):
            pass
    pp = os.path.join(root, "pyproject.toml")
    if os.path.exists(pp):
        body = open(pp, encoding="utf-8", errors="ignore").read()
        found = [t for t in PY_TOOL_SECTIONS if "[" + t in body]
        if found:
            tools["configs"] = [c + ("[" + ",".join(found) + "]" if c == "pyproject.toml" else "") for c in present]
    mk = os.path.join(root, "Makefile")
    if os.path.exists(mk):
        body = open(mk, encoding="utf-8", errors="ignore").read()
        for k in ("lint", "format", "fmt", "test", "check"):
            if re.search(r"^%s\s*:" % k, body, re.M):
                tools["commands"].setdefault(k, "make " + k)
    report["tooling"] = tools

    if a.json:
        print(json.dumps(report, indent=1, sort_keys=True))
        return 0
    print_text(report)
    return 0


def mix(counter):
    counter = collections.Counter(counter)
    total = sum(counter.values())
    if not total:
        return "none found"
    return ", ".join("%s %d%%" % (k, pct(v, total)) for k, v in counter.most_common(3)) + " (n=%d)" % total


def print_text(r):
    sk = sum(r["skipped"].values())
    print("STYLE COUNTS  root=%s  git=%s" % (r["root"], r["git"]))
    print("files listed %d | counted %d | skipped %d %s" % (
        r["files_listed"], r["files_counted"], sk, dict(r["skipped"]) if sk else ""))
    print("folders: " + ", ".join("%s %d" % (k, v) for k, v in list(r["folders"].items())[:15]))
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
        print("tests: %d files%s" % (t["files"], (" e.g. " + ", ".join(t["examples"])) if t["examples"] else ""))
        if d["examples"]:
            print("examples (read in full): " + ", ".join(d["examples"]))
        if d["outliers"]:
            print("outliers (read in full) %d total, showing %d:" % (d["outliers_total"], len(d["outliers"])))
            for o in d["outliers"]:
                print("  %s  [%s]" % (o["path"], "; ".join(o["flags"])))
        else:
            print("outliers: none")
    t = r["tooling"]
    print("\n== tooling")
    print("configs: " + (", ".join(t["configs"]) if t["configs"] else "none found"))
    print("commands: " + (", ".join("%s=%s" % kv for kv in t["commands"].items()) if t["commands"] else "none found"))


if __name__ == "__main__":
    sys.exit(main())
