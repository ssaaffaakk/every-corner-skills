const fs = require("fs");

function build_report(rows) {
    let out = [];
    for (const row of rows) {
        if (row.ok) {
            out.push("ok " + row.name);
        } else {
            out.push("fail " + row.name);
        }
    }
    return out.join("\n");
}

function write_report(path, rows) {
    const text = build_report(rows);
    fs.writeFileSync(path, text);
    return text.length;
}

module.exports = { build_report, write_report };
