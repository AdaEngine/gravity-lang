#!/usr/bin/env python3
"""Exercise ordered project sources, C/archive/WASM outputs and publication failures."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
tool = root / "tools/aot_build.py"


def run(args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=90).stdout


with tempfile.TemporaryDirectory(prefix="gravity-aot-export-") as directory:
    output = Path(directory)
    first = output / "first.ada"
    second = output / "second.ada"
    first.write_text("func helper() { return 42; }\n")
    second.write_text("func main() { return helper(); }\n")
    archive = output / "libproject.a"
    args = [sys.executable, str(tool), str(first), str(second), "--module", "project", "--output", str(archive)]
    run(args)
    mapping = json.loads((output / "project.sources.json").read_text())
    assert [item["path"] for item in mapping] == [str(first.resolve()), str(second.resolve())]
    assert mapping[1]["firstLine"] > mapping[0]["firstLine"]
    run(args[:-1] + [str(output / "project.c")])
    before = archive.read_bytes()
    second.write_text("func main() { return { return 1; }; }\n")
    assert subprocess.run(args, capture_output=True, timeout=90).returncode != 0
    assert archive.read_bytes() == before
    wasm = output / "testmod.wasm"
    run([sys.executable, str(tool), str(root / "test/aot/scalars.gravity"), "--module", "testmod", "--output", str(wasm),
         "--cc", os.environ.get("WASM_CC", os.environ.get("CC", "clang"))])
    run(["node", str(root / "test/aot/wasm_host.js"), str(wasm)])
print("AOT export: multiple sources, C/archive output, rollback, WASM execution and fuel limit passed")
