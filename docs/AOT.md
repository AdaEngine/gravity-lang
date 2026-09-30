# Experimental native AOT backend

Gravity owns native code generation, the standalone runtime ABI and the library
build tool. Hosts such as AdaEngine consume generated libraries; they do not
implement a second Gravity compiler.

The backend emits C11 from the checked Gravity AST. The existing host
compiler currently also produces an unused bytecode closure during frontend
validation. The generated library contains native function bodies, not embedded
bytecode, and execution does **not** require the Gravity VM or `libgravity`.

## Build and consume a library

```sh
make -j4
python3 tools/aot_build.py test/aot/scalars.gravity \
    --module gameplay --output /tmp/gameplay/libgameplay.a
```

The output directory contains `libgameplay.a`, `gameplay.c`, `gameplay.h` and
`gravity_aot_runtime.h` / `gravity_aot_objects.h`. Include `gameplay.h` and link the archive:

```c
#include "gameplay.h"
#include <string.h>

gravity_aot_context context = gravity_aot_context_init(100000);
const gravity_aot_module *module = gameplay_get_module();
if (module->abi_version == GRAVITY_AOT_ABI_VERSION) {
    for (uint32_t i = 0; i < module->count; ++i) {
        if (!strcmp(module->exports[i].name, "main")) {
            gravity_aot_value result = module->exports[i].call(&context, NULL, 0);
            /* Check context.error before reading result. */
        }
    }
}
```

To generate C without invoking a target compiler:

```sh
./gravity --emit-c source.gravity --module gameplay -o gameplay.c
```

`.ada` inputs use the same parser; the file extension is unrestricted.

## Cross compilation

The Gravity executable runs on the desktop host. Only the emitted C is compiled
for the destination. Pass the target triple and the destination SDK/sysroot to
the build tool; it forwards them to Clang using argument arrays, without a shell:

```sh
python3 tools/aot_build.py source.gravity --module gameplay \
    --target arm64-apple-ios16.0 \
    --sysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    --output /tmp/gameplay-ios/libgameplay.a
```

Device and Simulator require separate builds (for example,
`arm64-apple-ios16.0-simulator` with the Simulator SDK). An archive is specific
to an OS, architecture and ABI. It does not package the host engine, sign an app,
create an XCFramework or validate execution on the destination. `--cc`, `--ar`
and repeatable `--cflag=-flag` support explicit toolchain configuration.

Failed generation or target compilation leaves previously published artifacts
unchanged. Unsupported constructs produce a source-located compiler error and
never fall back to VM execution.

## Declarations, attributes and native objects

The experimental standalone ABI is now **version 2**. Rebuild both libraries and
hosts generated with ABI 1. Values represent Int, Bool, Float, null, literal
strings, native objects, lists, ranges and borrowed host handles. Native methods
and metadata live in the same archive; no Gravity VM is linked for execution.

`module->declarations` records classes/structs, fields, methods and functions,
including source file IDs, line/column, parent names, parameter names/types and
complete attribute arguments. Arguments preserve their labels and kinds:
identifiers, strings, signed Int/Float, Bool, null and recursively nested lists.
Attributes on local declarations are rejected rather than silently omitted.

Attribute names are host-defined. Gravity preserves `@system`, `@query`,
`@resource`, `@component`, `@export`, `@scriptable`, `@before`/`@after`, `@rpc`,
`@network_command`, `@replicated_component`, `@network_field`, `@local`, `@tool`
and custom annotations through this generic representation. **Preserving
metadata does not implement the host service:** the host must validate attribute
targets/arguments, register schemas, resolve dependencies and choose callbacks.
For example, RPC metadata plus a native method is not a network transport.
AdaScript UI views remain unavailable in AdaEngine; metadata alone does not enable
`@view` rendering or editor tool permissions.

`module->types` exposes stored field defaults and native method pointers. Hosts
can instantiate a type with `gravity_aot_construct`, bind query/resource fields
with `gravity_aot_set` and invoke `update`, `ready`, `fixedUpdate`, `event` and
`destroy` with `gravity_aot_call`. Methods named `event` are now accepted in class
and struct declarations. Self-field references compile to resolved field slots.
Classes preserve reference identity; assignment/parameter passing copies structs.
Stored field defaults currently must be scalar/string constants or null.

The host supplies allocation memory. One simple setup is:

```c
unsigned char memory[32768];
gravity_aot_arena arena = {memory, sizeof(memory), 0};
gravity_aot_context context = gravity_aot_context_init(100000);
context.allocate = gravity_aot_arena_allocate;
context.allocation_data = &arena;
```

Arena exhaustion reports `GRAVITY_AOT_MEMORY`. There is no garbage collector;
objects, lists and ranges remain valid only while their supplied storage remains
alive. Do not reset an arena while native instances or values still reference it.
Hosts should distinguish persistent instance storage from temporary invocation
storage. Concurrent mutation of a shared instance needs host synchronization.

## Host bridge and supported execution

`gravity_aot_host` provides property get/set, method calls and iteration callbacks.
Borrowed handles use `gravity_aot_host_ref(&context, pointer)`. Advance
`context.host_generation` at the end of a borrow scope and refresh bindings before
the next callback. Old handles fail with `GRAVITY_AOT_STALE_HANDLE` when used.
Only the C host can inspect their payload; source code uses ordinary properties
and method calls. Host iteration returns native scalar/object values or borrowed
rows, allowing a query bridge to mutate existing component data without allocating
one native instance per entity.

Supported execution includes positional function/method calls, constructors,
recursion, local/field/list assignment, numeric arithmetic/comparisons, literal
string comparison, `if`/`else`, `while`, `for` over lists/ranges or host iterables,
`break`/`continue` and `return`. Logical operators are eager, matching Gravity.
Floating `%` uses IEEE `remainder`, matching the VM; consumers need their target's
C math runtime when that operator is used (for example, `-lm` on Linux).

Native parameter annotations check Int/Bool/Float/String/List kinds and native
class identity. Host handles rely on the host's type contract. The dynamic VM
does not enforce parameter annotations. Contexts store the first error, fuel and
recursion depth. Fuel is consumed on function entry, each loop condition and
object construction; reset after errors. Native calls unwind their depth on error.

Closures, inheritance, nested/static classes, static/computed properties, maps,
string interpolation/concatenation, named/default arguments, `repeat`, async,
global mutable variables and bodyless function declarations remain unsupported.
The host bridge exposes external globals/functions through declared extern
bindings. Unsupported source constructs produce compile errors; missing bridge
operations and invalid runtime values produce context errors. Compilation and
execution never silently fall back to the VM.

## Engine-style proof fixture

```sh
python3 tools/aot_build.py test/aot/attributes.gravity \
    --module attributes --output /tmp/native-attributes/libattributes.a
clang -std=c11 -I/tmp/native-attributes test/aot/attributes_host.c \
    /tmp/native-attributes/libattributes.a -o /tmp/native-attributes/host
/tmp/native-attributes/host
```

The fixture exercises component/resource/network/tool metadata, real native
class/struct semantics, query filters and position updates through a C host,
scriptable lifecycle, an RPC-annotated method, UTF-8 field values and stale-borrow
errors. This proves the Gravity backend and generic host ABI. The AdaEngine
adapter/export path has not yet been connected to this ABI.

## Verification

```sh
make -j4
python3 test/aot/run_all.py
./gravity -t test/unittest
```

The AOT tests build and link a native archive without `libgravity`, compare its
result against VM execution, instrument generated code with address/undefined
behavior sanitizers, exercise ABI/error/termination cases, and verify that
unsupported source and missing SDKs do not replace existing output.

## Swift host facade

The `GravityAOT` SwiftPM product consumes canonical `CGravity` declarations and
provides `NativeModule`, immutable metadata snapshots, `NativeInstance`,
`NativeValue` and `NativeHostObject` callbacks. The facade owns a stable C context
and a bounded allocation pool, protects invocations with a module lock, and
invalidates borrowed host handles between calls. Instances retain their module;
there is no global VM or Swift-instance ownership cycle. For dynamically loaded
code, retain the library owner in the module initializer.

The AdaEngine adapter can be enabled during development using
`ADAENGINE_GRAVITY_PACKAGE_PATH` pointing at this checkout. It registers native
systems, component/resource schemas and scriptable factories in existing engine
infrastructure. Its native integration tests run actual ECS queries and lifecycle
callbacks against statically linked generated code. World/input/assets/network/UI
adapters and an Editor native export flow remain separate work.
