#include "attributes.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

enum { POSITION=1, QUERY, CONTEXT, WORLD };
typedef struct { int kind; double x; int active, visible, paused; } position;
typedef struct { int kind; } handle;
typedef struct {
    position positions[4];
    handle query, context, world;
    gravity_aot_context *ctx;
    const gravity_aot_attribute *query_metadata;
    int notified;
} host_world;

static const gravity_aot_class *type(const char *name) {
    const gravity_aot_module *m=attributes_get_module();
    assert(m->abi_version==GRAVITY_AOT_ABI_VERSION);
    for (uint32_t i=0; i<m->type_count; ++i) if (!strcmp(m->types[i].declaration->name,name)) return &m->types[i];
    assert(!"missing native type"); return NULL;
}
static const gravity_aot_attribute *attribute(const gravity_aot_declaration *d,const char *name) {
    for (uint32_t i=0; i<d->attribute_count; ++i) if (!strcmp(d->attributes[i].name,name)) return &d->attributes[i];
    assert(!"missing attribute"); return NULL;
}
static const gravity_aot_attribute_value *arg(const gravity_aot_attribute *a,const char *label) {
    for (uint32_t i=0; i<a->argument_count; ++i) {
        const gravity_aot_attribute_argument *v=&a->arguments[i];
        if ((!label && !v->label) || (label && v->label && !strcmp(label,v->label))) return v->value;
    }
    assert(!"missing argument"); return NULL;
}
static const gravity_aot_declaration *field(const char *class_name,const char *name) {
    const gravity_aot_class *t=type(class_name);
    for (uint32_t i=0; i<t->field_count; ++i) if (!strcmp(t->fields[i].declaration->name,name)) return t->fields[i].declaration;
    assert(!"missing field"); return NULL;
}
static int flag(position *p,const char *name) {
    if (!strcmp(name,"Active")) return p->active;
    if (!strcmp(name,"Visible")) return p->visible;
    if (!strcmp(name,"Paused")) return p->paused;
    assert(!"unknown query filter"); return 0;
}
static int get(void *data,gravity_aot_value receiver,const char *key,gravity_aot_value *value) {
    host_world *w=(host_world *)data;
    int kind=((handle *)receiver.handle)->kind;
    if (kind==POSITION) {
        if (!strcmp(key,"Position")) { *value=receiver; return 1; }
        if (!strcmp(key,"x")) { *value=gravity_aot_float(((position *)receiver.handle)->x); return 1; }
    }
    if (kind==CONTEXT) {
        if (!strcmp(key,"deltaTime")) { *value=gravity_aot_float(0.5); return 1; }
        if (!strcmp(key,"bonus")) { *value=gravity_aot_int(3); return 1; }
        if (!strcmp(key,"world")) { *value=gravity_aot_host_ref(w->ctx,&w->world); return 1; }
    }
    return 0;
}
static int set(void *data,gravity_aot_value receiver,const char *key,gravity_aot_value value) {
    (void)data;
    if (((handle *)receiver.handle)->kind==POSITION && !strcmp(key,"x") && value.kind==GRAVITY_AOT_FLOAT) {
        ((position *)receiver.handle)->x=value.floating; return 1;
    }
    return 0;
}
static int call(void *data,gravity_aot_value receiver,const char *key,const gravity_aot_value *args,uint32_t count,gravity_aot_value *result) {
    host_world *w=(host_world *)data;
    if (receiver.kind==GRAVITY_AOT_HOST && ((handle *)receiver.handle)->kind==WORLD && !strcmp(key,"notify") && count==1) {
        w->notified=(int)args[0].integer; *result=gravity_aot_null(); return 1;
    }
    return 0;
}
static int next(void *data,gravity_aot_value receiver,uint64_t *state,gravity_aot_value *value) {
    host_world *w=(host_world *)data;
    assert(receiver.kind==GRAVITY_AOT_HOST && receiver.handle==&w->query);
    const gravity_aot_attribute_value *with=arg(w->query_metadata,"with"), *without=arg(w->query_metadata,"without");
    while (*state<4) {
        position *p=&w->positions[(*state)++]; int match=1;
        for (uint32_t i=0; i<with->count; ++i) if (!flag(p,with->items[i]->text)) match=0;
        if (flag(p,without->text)) match=0;
        if (match) { *value=gravity_aot_host_ref(w->ctx,p); return 1; }
    }
    return 0;
}
int main(void) {
    unsigned char memory[32768];
    gravity_aot_arena arena={memory,sizeof(memory),0};
    gravity_aot_context c=gravity_aot_context_init(100000);
    c.allocate=gravity_aot_arena_allocate; c.allocation_data=&arena;
    const gravity_aot_module *module=attributes_get_module();
    assert(module->count==1 && module->type_count==8);
    gravity_aot_value value=module->exports[0].call(&c,NULL,0);
    assert(!c.error && !c.depth && value.kind==GRAVITY_AOT_FLOAT && value.floating==18.0);
    printf("RESULT: %.0f\n",value.floating);
    const gravity_aot_attribute *custom=attribute(module->exports[0].declaration,"metadata");
    const gravity_aot_attribute_value *items=arg(custom,"values");
    assert(items->kind==GRAVITY_AOT_ATTR_LIST && items->count==7);
    assert(items->items[0]->kind==GRAVITY_AOT_ATTR_IDENTIFIER && !strcmp(items->items[0]->text,"Position"));
    assert(items->items[1]->kind==GRAVITY_AOT_ATTR_STRING && !strcmp(items->items[1]->text,"text"));
    assert(items->items[2]->integer==-3 && items->items[3]->floating==2.5 && items->items[4]->integer==1);
    assert(items->items[5]->kind==GRAVITY_AOT_ATTR_NULL && !strcmp(items->items[6]->items[0]->text,"nested"));
    assert(strstr(arg(custom,"note")->text,"\"") && custom->line>0 && module->exports[0].declaration->line>0);
    assert(!strcmp(arg(attribute(type("Position")->declaration,"component"),"id")->text,"aot.position"));
    assert(arg(attribute(type("Time")->declaration,"resource"),"autoInsert")->integer==1);
    assert(arg(attribute(type("Health")->declaration,"replicated_component"),"version")->integer==2);
    assert(arg(attribute(field("Health","value"),"network_field"),"tag")->integer==1);
    assert(attribute(field("Health","dirty"),"local")->argument_count==0);
    assert(attribute(type("Hit")->declaration,"network_command"));
    assert(attribute(type("Tool")->declaration,"tool"));
    assert(attribute(field("Controller","health"),"export"));
    const gravity_aot_class *movement=type("Movement");
    assert(!strcmp(arg(attribute(movement->declaration,"system"),"scheduler")->text,"update"));
    assert(!strcmp(arg(attribute(movement->declaration,"after"),"id")->text,"input"));
    assert(!strcmp(arg(attribute(movement->declaration,"before"),"id")->text,"render"));
    for (uint32_t i=0; i<movement->method_count; ++i)
        if (!strcmp(movement->methods[i].name,"damage")) {
            const gravity_aot_declaration *d=movement->methods[i].declaration;
            assert(attribute(d,"rpc") && d->parameter_count==1 && !strcmp(d->parameters[0].name,"amount") && !strcmp(d->parameters[0].type_name,"Int"));
        }
    host_world world={.positions={{POSITION,1,1,1,0},{POSITION,10,1,1,1},{POSITION,20,1,0,0},{POSITION,30,1,1,0}},
                      .query={QUERY},.context={CONTEXT},.world={WORLD},.ctx=&c,.query_metadata=attribute(field("Movement","rows"),"query")};
    static const gravity_aot_host bridge={get,set,call,next}; c.host=&bridge; c.host_data=&world;
    gravity_aot_value system=gravity_aot_construct(&c,movement,NULL,0);
    gravity_aot_value timing=gravity_aot_construct(&c,type("Time"),NULL,0);
    assert(gravity_aot_set(&c,system,"rows",gravity_aot_host_ref(&c,&world.query)));
    assert(gravity_aot_set(&c,system,"timing",timing));
    gravity_aot_value context=gravity_aot_host_ref(&c,&world.context);
    (void)gravity_aot_call(&c,system,"update",&context,1);
    (void)gravity_aot_call(&c,system,"update",&context,1);
    assert(!c.error && !c.depth && world.positions[0].x==3 && world.positions[3].x==32);
    assert(world.positions[1].x==10 && world.positions[2].x==20 && world.notified==2);
    gravity_aot_value damage=gravity_aot_int(4);
    (void)gravity_aot_call(&c,system,"damage",&damage,1);
    assert(!c.error && gravity_aot_get(&c,system,"calls").integer==6);
    gravity_aot_value controller=gravity_aot_construct(&c,type("Controller"),NULL,0);
    assert(gravity_aot_set(&c,controller,"position",gravity_aot_host_ref(&c,&world.positions[0])));
    assert(gravity_aot_set(&c,controller,"clock",timing));
    (void)gravity_aot_call(&c,controller,"ready",&context,1);
    (void)gravity_aot_call(&c,controller,"update",&context,1);
    (void)gravity_aot_call(&c,controller,"fixedUpdate",&context,1);
    (void)gravity_aot_call(&c,controller,"event",&context,1);
    assert(!c.error && gravity_aot_get(&c,controller,"health").integer==15 && world.positions[0].x==3.5);
    gravity_aot_value label=gravity_aot_get(&c,controller,"label");
    assert(label.kind==GRAVITY_AOT_STRING && label.length==6 && !memcmp(label.string,"日本",6));
    (void)gravity_aot_call(&c,controller,"destroy",&context,1);
    assert(!c.error && gravity_aot_get(&c,controller,"health").integer==0);
    /* Borrowed field bindings must be refreshed after a host generation change. */
    ++c.host_generation; context=gravity_aot_host_ref(&c,&world.context);
    (void)gravity_aot_call(&c,system,"update",&context,1);
    assert(c.error==GRAVITY_AOT_STALE_HANDLE && !c.depth);
    c.error=0;
    (void)gravity_aot_call(&c,system,"missing",NULL,0);
    assert(c.error==GRAVITY_AOT_METHOD && !c.depth);
    c.error=0;
    gravity_aot_get(&c,system,"missing"); assert(c.error==GRAVITY_AOT_FIELD);
    gravity_aot_context tiny=gravity_aot_context_init(100);
    gravity_aot_value failed=gravity_aot_construct(&tiny,movement,NULL,0);
    assert(tiny.error==GRAVITY_AOT_MEMORY && failed.kind==GRAVITY_AOT_NULL);
    puts("ATTRIBUTES: metadata, native systems/query filters/resources, RPC method and scriptable lifecycle passed");
    return 0;
}
