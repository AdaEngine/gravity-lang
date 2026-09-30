#!/usr/bin/env python3
"""End-to-end native archive, differential VM and fail-closed AOT tests."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent.parent
gravity = root / "gravity"
cc = os.environ.get("CC", "clang")
math_libraries = ["-lm"] if sys.platform != "win32" else []


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        result.check_returncode()
    return result.stdout


with tempfile.TemporaryDirectory(prefix="gravity-aot-tests-") as tmp:
    out = Path(tmp)
    library = out / "libtestmod.a"
    source = root / "test/aot/scalars.gravity"
    run([sys.executable, str(root / "tools/aot_build.py"), str(source), "--module", "testmod",
         "--cc", cc, "--output", str(library)])
    # The host links only the generated archive: no libgravity or VM.
    host = out / "host"
    run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-I", str(out),
         str(root / "test/aot/host.c"), str(library), "-o", str(host)] + math_libraries)
    native = run([str(host)])
    vm = run([str(gravity), str(source)])
    assert re.search(r"RESULT:\s*(?:\(INT\)\s*)?(-?\d+)", native).group(1) == re.search(r"RESULT:\s*(?:\(INT\)\s*)?(-?\d+)", vm).group(1), (native, vm)
    # Instrument generated code too, not just the host.
    run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-I", str(out),
         str(root / "test/aot/host.c"), str(out / "testmod.c"), "-o", str(host)] + math_libraries)
    run([str(host)])
    cases = [
        "class Player: Object {}",
        "class Player { var x = [1,2]; }",
        'func main() { return ["key":1]; }',
        "func main() { return { return 1; }; }",
        "var global = 1; func main() { return global; }",
        "class Outer { class Inner {} }",
        "func main() { repeat {} while (false); }",
        "func main(a = 1) { return a; }",
        "class Player { static func main() { return 1; } }",
        "func main() { var x = 1; func nested() { return x; } return nested(); }",
        "func main() { @export var x = 1; return x; }",
        "async func main() { return 1; }",
        "func main() { return missing; }",
    ]
    for index, text in enumerate(cases):
        bad = out / f"unsupported{index}.gravity"
        bad.write_text(text)
        generated = out / "unchanged.c"
        generated.write_text("preserve existing output")
        result = subprocess.run([str(gravity), "--emit-c", str(bad), "--module", "bad", "-o", str(generated)], capture_output=True)
        assert result.returncode != 0, (text, result.stdout)
        assert generated.read_text() == "preserve existing output", text
    for prefix in ["bad-name", "0prefix", "_reserved", ""]:
        result = subprocess.run([str(gravity), "--emit-c", str(source), "--module", prefix, "-o", str(out / "bad.c")], capture_output=True)
        assert result.returncode != 0
    # Compare individual scalar semantics against the VM, including conversions.
    expressions = ["1 + 2 * 3", "-7 / 3", "-7 % 3", "-(-4)", "true + 2",
                   "1 == true", "null == 0", "null + true", "null - 4", "null / 2",
                   "null % 2", "-null", "!null", "1 && 0", "false || 3", "1 < true",
                   "null >= false", "true != false", "9223372036854775807 + 1",
                   "1 - (-2)", "true * false", "null * 5", "0 != null", "+true"]
    driver = out / "probe_host.c"
    driver.write_text('''#include "probe.h"
#include <stdio.h>
int main(void) {
    gravity_aot_context c = gravity_aot_context_init(1000);
    gravity_aot_value v = probe_get_module()->exports[0].call(&c, NULL, 0);
    if (c.error) return 1;
    if (v.kind == GRAVITY_AOT_BOOL) puts(v.integer ? "true" : "false");
    else if (v.kind == GRAVITY_AOT_NULL) puts("null");
    else if (v.kind == GRAVITY_AOT_FLOAT) printf("%.15g\\n", v.floating);
    else if (v.kind == GRAVITY_AOT_STRING) printf("%.*s\\n", (int)v.length, v.string);
    else printf("%lld\\n", (long long)v.integer);
    return 0;
}
''')
    expressions += ["1.5 + 2", "2 + 1.5", "1.5 * 2", "5 / 2.0", "5.5 % 2", "5 % 2.5",
                    "-1.5", "true + 2.5", "null - 2.5", "1 < 1.5", "1.0 == 1", "!0.0",
                    '"same" == "same"', '"a" < "b"', '"日本" == "日本"']
    error_expressions = ["null / 0", "null % 0", "1 / null", "1 % null", "1 / false", "0 / 0"]
    for expression in expressions + error_expressions:
        probe = out / "probe.gravity"
        probe.write_text("func main() { return " + expression + "; }")
        run([sys.executable, str(root / "tools/aot_build.py"), str(probe), "--module", "probe",
             "--output", str(out / "libprobe.a"), "--cc", cc])
        run([cc, "-std=c99", "-fsanitize=address,undefined", "-I", str(out), str(driver),
             str(out / "probe.c"), "-o", str(out / "probe_host")] + math_libraries)
        vm_output = run([str(gravity), str(probe)])
        if expression in error_expressions:
            assert subprocess.run([str(out / "probe_host")], capture_output=True).returncode == 1
            assert "RUNTIME ERROR:" in vm_output, (expression, vm_output)
            continue
        native_value = run([str(out / "probe_host")]).strip()
        vm_match = re.search(r"RESULT:\s*(?:\(\w+\)\s*)?(\S+)", vm_output)
        assert vm_match, (expression, vm_output)
        vm_value = vm_match.group(1)
        assert native_value == vm_value, (expression, native_value, vm_value)
    # Class/struct metadata and native engine-style host callbacks.
    attribute_source = root / "test/aot/attributes.gravity"
    attribute_library = out / "libattributes.a"
    run([sys.executable, str(root / "tools/aot_build.py"), str(attribute_source), "--module", "attributes",
         "--output", str(attribute_library), "--cc", cc])
    attribute_host = out / "attributes_host"
    run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-I", str(out),
         str(root / "test/aot/attributes_host.c"), str(attribute_library), "-o", str(attribute_host)] + math_libraries)
    attribute_native = run([str(attribute_host)])
    attribute_vm = run([str(gravity), str(attribute_source)])
    assert re.search(r"RESULT: (\d+)", attribute_native).group(1) == re.search(r"RESULT: \(FLOAT\) (\d+)", attribute_vm).group(1)
    run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-I", str(out),
         str(root / "test/aot/attributes_host.c"), str(out / "attributes.c"), "-o", str(attribute_host)] + math_libraries)
    run([str(attribute_host)])
    # A missing target SDK must leave a previously built library intact.
    before = library.read_bytes()
    failed = subprocess.run([sys.executable, str(root / "tools/aot_build.py"), str(source), "--module", "testmod",
                             "--output", str(library), "--sysroot", str(out / "missing-sdk")], capture_output=True)
    assert failed.returncode != 0 and library.read_bytes() == before
print("AOT: native archive, VM comparison, sanitizers, ABI/errors/limits, 45 scalar comparisons and annotated native objects/host callbacks and 13 rejection cases passed")
