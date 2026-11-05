// Starts the database worker (db_worker.wasm, compiled by dart2wasm) in
// this module worker. A browser without WebAssembly GC gets an error reply.
import * as loader from './db_worker.mjs';

try {
  const app = await loader.compileStreaming(fetch(new URL('./db_worker.wasm', import.meta.url)));
  const instance = await app.instantiate({});
  instance.invokeMain();
} catch (e) {
  postMessage(JSON.stringify({unsupported: String(e)}));
}
