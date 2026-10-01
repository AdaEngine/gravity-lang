#!/usr/bin/env python3
"""Execute the same native coroutine proof on macOS and freestanding WASM."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
r=Path(__file__).resolve().parents[2]
cc=os.environ.get('CC','clang')
wasmcc=os.environ.get('WASM_CC',cc)
def run(args):
    return subprocess.run(args,check=True,text=True,capture_output=True,timeout=90).stdout
with tempfile.TemporaryDirectory(prefix='gravity-native-async-') as directory:
    out=Path(directory)
    run([sys.executable,str(r/'tools/aot_build.py'),str(r/'test/aot/async.gravity'),'--module','asyncproof','--output',str(out/'libasyncproof.a'),'--cc',cc])
    run([cc,'-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I',str(out),str(r/'test/aot/async_host.c'),str(out/'asyncproof.c'),'-o',str(out/'async-host'),'-lm'])
    print(run([str(out/'async-host')]).strip())
    wasm=out/'async.wasm'
    run([wasmcc,'--target=wasm32-unknown-unknown','-std=c11','-O2','-nostdlib','-fno-builtin','-DGA_WASM_TEST','-I',str(out),str(r/'test/aot/async_host.c'),str(out/'asyncproof.c'),'-Wl,--no-entry','-Wl,--export=asyncproof_run','-o',str(wasm)])
    print(run(['node','-e',"const fs=require('fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));if(WebAssembly.Module.imports(m).length)throw Error('Unexpected VM/runtime import');const i=new WebAssembly.Instance(m);const result=i.exports.asyncproof_run();if(result)throw Error('Async proof failed on line '+result);console.log('WASM async: same coroutine proof passed, no runtime imports');",str(wasm)]).strip())
