#include "testmod.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static gravity_aot_function find(const char *name) {
    const gravity_aot_module *m = testmod_get_module();
    assert(m->abi_version == GRAVITY_AOT_ABI_VERSION);
    for (uint32_t i = 0; i < m->count; ++i) if (!strcmp(name, m->exports[i].name)) return m->exports[i].call;
    assert(!"missing export"); return NULL;
}
int main(void) {
    gravity_aot_context c = gravity_aot_context_init(10000);
    gravity_aot_value v = find("main")(&c, NULL, 0);
    assert(!c.error && !c.depth && v.kind == GRAVITY_AOT_INT && v.integer == 756);
    printf("RESULT: %lld\n", (long long)v.integer);
    v = find("wrap")(&c, NULL, 0);
    assert(!c.error && v.integer == INT64_MIN);
    gravity_aot_value args[] = {gravity_aot_int(9), gravity_aot_int(0)};
    find("divide")(&c, args, 2);
    assert(c.error == GRAVITY_AOT_DIV_ZERO && !c.depth);
    c = gravity_aot_context_init(100);
    find("add")(&c, args, 1);
    assert(c.error == GRAVITY_AOT_ARITY && !c.depth);
    c = gravity_aot_context_init(100);
    args[0] = gravity_aot_bool(1);
    find("add")(&c, args, 2);
    assert(c.error == GRAVITY_AOT_TYPE && !c.depth);
    c = gravity_aot_context_init(100);
    c.abi_version = 999;
    find("empty")(&c, NULL, 0);
    assert(c.error == GRAVITY_AOT_BAD_ABI && !c.depth);
    c = gravity_aot_context_init(10);
    find("infinite")(&c, NULL, 0);
    assert(c.error == GRAVITY_AOT_LIMIT && !c.depth);
    c = gravity_aot_context_init(10000);
    c.max_depth = 3;
    args[0] = gravity_aot_int(10);
    find("fact")(&c, args, 1);
    assert(c.error == GRAVITY_AOT_LIMIT && !c.depth);
    c = gravity_aot_context_init(100);
    args[0] = gravity_aot_bool(0);
    v = find("logic")(&c, args, 1);
    assert(!c.error && v.kind == GRAVITY_AOT_BOOL && v.integer == 1);
    v = find("empty")(&c, NULL, 0);
    assert(!c.error && v.kind == GRAVITY_AOT_NULL);
    return 0;
}
