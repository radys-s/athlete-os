const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function boot(lock, supported = true) {
  const elements = [];
  const document = {
    createElement: tag => ({tag, setAttribute() {}, style: {}}),
    body: {appendChild: e => elements.push(e)},
  };
  const navigator = supported ? {locks: {request: (_, options, callback) => {
    assert.equal(options.ifAvailable, true);
    callback(lock);
    return Promise.resolve();
  }}} : {};
  vm.runInNewContext(fs.readFileSync('web/app_bootstrap.js', 'utf8'), {document, navigator});
  return elements;
}

test('Flutter only loads after acquiring the storage lock', () => {
  assert.equal(boot({}).filter(e => e.src === 'flutter_bootstrap.js').length, 1);
  assert.equal(boot(null).filter(e => e.tag === 'script').length, 0);
  assert.match(boot(null)[0].textContent, /jiném okně/);
  assert.equal(boot(null, false).filter(e => e.tag === 'script').length, 0);
});

test('failed required precache does not activate the new worker', async () => {
  const handlers = {};
  let skipped = false;
  const self = {
    addEventListener: (name, handler) => handlers[name] = handler,
    skipWaiting: () => { skipped = true; },
  };
  let deleted = false;
  const caches = {delete: async () => { deleted = true; }, open: async () => ({addAll: async urls => {
    assert.ok(urls.includes('./app_bootstrap.js'));
    assert.ok(urls.includes('./sqlite3.wasm'));
    throw Error('network interrupted');
  }})};
  vm.runInNewContext(fs.readFileSync('web/service_worker.js', 'utf8'), {self, caches});
  let install;
  handlers.install({waitUntil: promise => install = promise});
  await assert.rejects(install, /network interrupted/);
  assert.equal(skipped, false);
  assert.equal(deleted, true);
});
