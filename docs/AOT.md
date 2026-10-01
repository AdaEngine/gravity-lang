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

The experimental standalone ABI is now **version 3**. Rebuild both libraries and
hosts generated with ABI 1 or 2. Values represent Int, Bool, Float, null, literal
strings, native objects, lists, ranges, native tasks and borrowed/durable host handles. Native methods
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
string interpolation/concatenation, named/default arguments, `repeat`,
global mutable variables and bodyless function declarations remain unsupported.
The host bridge exposes external globals/functions through declared extern
bindings. Unsupported source constructs produce compile errors; missing bridge
operations and invalid runtime values produce context errors. Compilation and
execution never silently fall back to the VM.

## Native async and await

Use `gravity_compiler_prepare_native` before `gravity_compiler_emit_c` in C hosts.
The CLI and `aot_build.py` already do this. It preserves async AST bodies rather
than lowering them into VM Fiber wrappers; semantic checking remains shared.

An async call creates a suspended coroutine and returns a native
`GRAVITY_AOT_TASK`. Generated resume functions use a program counter and an
arena-owned frame for locals, expression temporaries, argument arrays and loop
cursors. `gravity_aot_task_poll` continues from that point without replaying side
effects. Awaiting a child task propagates completion, errors and cancellation.
Promise tasks created with a null resume callback support `complete(value)`,
`isComplete()`, `status()`, `result()` and `cancel()`. Nonconstant field defaults,
including promise construction, run through generated initializer callbacks;
struct copies do not rerun initializers.

Awaitable host operations use `GRAVITY_AOT_DURABLE_HOST` and expose `isDone()`,
`result()` and `cancel()`. Only detached, synchronized operations may be durable.
Ordinary host handles retain the callback generation and fail on later access.
Explicit `@nonsendable` objects cannot cross suspension, including nested values;
the frame check is conservative and can also reject dead nonsendable temporaries.
Polls consume the same fuel/depth budget as synchronous native calls. Arena
memory remains bounded and caller-owned; native tasks do not introduce a C-object GC.
The Swift facade traces detached host handles from live instances/tasks and their
native references, periodically releasing unreachable timer/operation adapters.
Durable handle generations prevent a reused Swift address from reviving an old
reference. Completed/cancelled task frames release their suspended references.

The Swift facade adds `NativeValue.task`, `NativeTask`, `NativeModule.poll/cancel`,
`makePromise` and `NativeSuspensionSafeHostObject`. The facade starts scheduled tasks after synchronous callback statements finish,
while the callback scope is still valid. Hosts must arrange subsequent polling
inside valid owner access and cancel tasks when that owner goes away. AdaEngine
provides this scheduling plus Tasks/Time/async asset adapters for Editor exports.

```sh
python3 test/aot/async.py
```

This executes the same coroutine proof with ASan/UBSan and freestanding WASM:
nested await, loops and expression state, immediate completion, no replay, promises,
cancellation, stale capabilities, errors and fuel. No VM runtime is linked.

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
errors. This proves the Gravity backend and generic host ABI. AdaEngine consumes this ABI through its GravityAOT facade and native runtime adapters.

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
callbacks against statically linked generated code. World commands, input, assets and networking now have native adapters in AdaEngine. Standalone macOS AdaEditor can generate a native game package and export its macOS app or game-specific WebAssembly bundle; AdaScript UI views remain unavailable.

## Project sources and export formats

The build tool accepts multiple ordered sources as one module and writes
`<module>.sources.json` with their merged-source line ranges. It accepts `.c`
output for host build systems and `.wasm` for standalone wasm32 C-ABI hosts:

```sh
python3 tools/aot_build.py Components.ada Gameplay.ada --module gameplay \
    --output /tmp/gameplay/gameplay.c
python3 tools/aot_build.py test/aot/scalars.gravity --module testmod \
    --cc /path/to/wasm-capable/clang --output /tmp/gameplay/testmod.wasm
```

The standalone WASM exports linear memory, its indirect function table and the
module accessor. It imports only the target math operation `env.remainder` when
required by generated numeric operations. Hosts must provide IEEE remainder
semantics. It is an ABI module, not a complete browser game or an AdaEngine player.
AdaEditor's Web export compiles the same generated C into its game-specific
Swift/WASI executable and uses the engine's browser bundler.

`NativeModule.invoke` accepts callback-scoped extern globals. A host callback can
read a native command argument's fields under the same module lock without a
nested invocation. Borrowed globals are cleared after the invocation.

```sh
WASM_CC=/path/to/wasm-capable/clang python3 test/aot/export_formats.py
```

This checks ordered sources, C/archive formats, failure preservation, actual
WASM scalar execution and the fuel limit. On current macOS, use a recent Clang
sanitizer runtime for `run_all.py`; older Apple ASan runtimes can deadlock during
initialization before generated code runs.
