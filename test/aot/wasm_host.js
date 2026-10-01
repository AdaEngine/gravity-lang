// Minimal wasm32 C-ABI host for the scalar proof. It consumes only the module
// accessor, memory and native function table; no Gravity VM or JS interpreter.
const fs = require('fs');
const assert = require('assert/strict');
const moduleCode = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
assert.deepEqual(WebAssembly.Module.imports(moduleCode), [{ module: 'env', name: 'remainder', kind: 'function' }]);
const instance = new WebAssembly.Instance(moduleCode, { env: { remainder: () => { throw Error('Scalar proof must not call float remainder'); } } });
const { memory, __indirect_function_table: table, testmod_get_module: getModule } = instance.exports;
const descriptor = getModule();
const context = memory.buffer.byteLength;
memory.grow(1);
const view = new DataView(memory.buffer);
assert.equal(view.getUint32(descriptor, true), 3);
const text = pointer => {
    const bytes = new Uint8Array(memory.buffer);
    let end = pointer;
    while (bytes[end]) end++;
    return new TextDecoder().decode(bytes.subarray(pointer, end));
};
const count = view.getUint32(descriptor + 4, true);
const exportsPointer = view.getUint32(descriptor + 8, true);
const methods = {};
for (let index = 0; index < count; index++) {
    const entry = exportsPointer + index * 16;
    methods[text(view.getUint32(entry, true))] = table.get(view.getUint32(entry + 8, true));
}
const reset = fuel => {
    new Uint8Array(memory.buffer, context, 48).fill(0);
    view.setUint32(context, 3, true);
    view.setBigUint64(context + 8, BigInt(fuel), true);
    view.setUint32(context + 20, 64, true);
};
reset(10000);
methods.main(context + 128, context, 0, 0);
assert.equal(view.getUint32(context + 4, true), 0);
assert.equal(view.getBigInt64(context + 128, true), 756n);
reset(10);
methods.infinite(context + 128, context, 0, 0);
assert.equal(view.getUint32(context + 4, true), 5);
assert.equal(view.getUint32(context + 16, true), 0);
console.log('WASM native execution: 756; infinite loop stopped by fuel');
