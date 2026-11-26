import re


def clean_text(value):
    """Remove odd characters."""
    out = []
    for ch in value:
        if re.match("[a-z]", ch):
            out.append(ch)
        else:
            out.append("_")
    return "".join(out)


def split_words(value):
    parts = []
    for word in value.split(" "):
        if word != "":
            parts.append(word)
        else:
            continue
    return parts
