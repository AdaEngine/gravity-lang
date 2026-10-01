#include "asyncproof.h"
#ifndef GA_WASM_TEST
#include <stdio.h>
#endif
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
static unsigned char bytes[65536];
static unsigned frame, calls, cancelled;
static struct { unsigned frame, cancelled; } operations[64];
static int get(void *data,gravity_aot_value receiver,const char *name,gravity_aot_value *out) {
    gravity_aot_context *ctx=(gravity_aot_context *)data;
    if (receiver.kind==GRAVITY_AOT_NULL) { *out=gravity_aot_host_ref(ctx,(void *)1); return 1; }
    if (!gravity_aot_text_compare(name,"value")) { *out=gravity_aot_int(42); return 1; }
    return 0;
}
static int call(void *data,gravity_aot_value receiver,const char *name,const gravity_aot_value *args,uint32_t count,gravity_aot_value *out) {
    (void)args; (void)count;
    gravity_aot_context *ctx=(gravity_aot_context *)data;
    if (!gravity_aot_text_compare(name,"promise")) { *out=gravity_aot_task_new(ctx,NULL,0,0); return 1; }
    if (!gravity_aot_text_compare(name,"nextFrame")) {
        if (calls>=64) return 0;
        operations[calls].frame=frame+1; operations[calls].cancelled=0;
        *out=gravity_aot_null(); out->kind=GRAVITY_AOT_DURABLE_HOST; out->handle=&operations[calls++]; return 1;
    }
    unsigned *operation=(unsigned *)receiver.handle;
    if (!gravity_aot_text_compare(name,"isDone")) { *out=gravity_aot_bool(frame>=operation[0] || operation[1]); return 1; }
    if (!gravity_aot_text_compare(name,"result")) { *out=gravity_aot_null(); return 1; }
    if (!gravity_aot_text_compare(name,"cancel")) { ++cancelled; operation[1]=1; *out=gravity_aot_null(); return 1; }
    return 0;
}
static gravity_aot_function function(const gravity_aot_module *m,const char *name) {
    for (uint32_t i=0;i<m->count;++i) if (!gravity_aot_text_compare(m->exports[i].name,name)) return m->exports[i].call;
    return NULL;
}
int asyncproof_run(void) {
    frame=calls=cancelled=0;
    gravity_aot_context ctx=gravity_aot_context_init(10000);
    gravity_aot_arena arena={bytes,sizeof(bytes),0};
    gravity_aot_host host={.get=get,.call=call};
    ctx.allocate=gravity_aot_arena_allocate; ctx.allocation_data=&arena; ctx.host=&host; ctx.host_data=&ctx;
    const gravity_aot_module *m=asyncproof_get_module();
    gravity_aot_value task=function(m,"work")(&ctx,NULL,0),result=gravity_aot_null();
    CHECK(!ctx.error && task.kind==GRAVITY_AOT_TASK && calls==0);
    CHECK(!gravity_aot_task_poll(&ctx,task,&result) && calls==1);
    for(frame=1;frame<3;frame++) { CHECK(!gravity_aot_task_poll(&ctx,task,&result)); CHECK(!ctx.error && calls==frame+1); }
    CHECK(gravity_aot_task_poll(&ctx,task,&result) && !ctx.error && result.integer==12 && calls==3);
    task=function(m,"work")(&ctx,NULL,0); CHECK(!ctx.error); CHECK(!gravity_aot_task_poll(&ctx,task,&result));
    gravity_aot_task_cancel(&ctx,task); CHECK(cancelled==1 && task.task->state==GA_TASK_CANCELLED);
    task=function(m,"immediate")(&ctx,NULL,0); CHECK(gravity_aot_task_poll(&ctx,task,&result) && result.integer==9);
    gravity_aot_value owner=gravity_aot_construct(&ctx,&m->types[0],NULL,0);
    CHECK(!ctx.error);
    task=gravity_aot_call(&ctx,owner,"wait",NULL,0); CHECK(!ctx.error); CHECK(!gravity_aot_task_poll(&ctx,task,&result));
    (void)gravity_aot_call(&ctx,owner,"reply",NULL,0); (void)gravity_aot_call(&ctx,owner,"reply",NULL,0);
    CHECK(gravity_aot_task_poll(&ctx,task,&result) && result.integer==42);
    gravity_aot_value capability=gravity_aot_host_ref(&ctx,(void*)1);
    task=function(m,"stale")(&ctx,&capability,1); CHECK(!ctx.error); CHECK(!gravity_aot_task_poll(&ctx,task,&result));
    ++frame; ++ctx.host_generation;
    CHECK(!gravity_aot_task_poll(&ctx,task,&result) && ctx.error==GRAVITY_AOT_STALE_HANDLE);
    ctx.error=0;
    task=function(m,"failure")(&ctx,NULL,0); CHECK(!ctx.error); CHECK(!gravity_aot_task_poll(&ctx,task,&result)); ++frame;
    CHECK(!gravity_aot_task_poll(&ctx,task,&result) && ctx.error==GRAVITY_AOT_DIV_ZERO);
    ctx.error=0;
    gravity_aot_value locked=gravity_aot_construct(&ctx,&m->types[1],NULL,0);
    gravity_aot_value captured=gravity_aot_list_new(&ctx,&locked,1);
    unsigned before=cancelled;
    task=function(m,"unsafeCapture")(&ctx,&captured,1);
    (void)gravity_aot_task_poll(&ctx,task,&result);
    CHECK(ctx.error==GRAVITY_AOT_TYPE && cancelled==before+1);
    ctx.error=0; ctx.fuel=8;
    task=function(m,"infinite")(&ctx,NULL,0); (void)gravity_aot_task_poll(&ctx,task,&result); CHECK(ctx.error==GRAVITY_AOT_LIMIT && ctx.depth==0);
    return 0;
}
#ifndef GA_WASM_TEST
int main(void) { int error=asyncproof_run(); if (error) { printf("Async failed on line %d\n",error); return 1; } puts("Native async: nested await, loops, no replay, promises, cancellation, stale capabilities, errors/fuel passed"); }
#endif
