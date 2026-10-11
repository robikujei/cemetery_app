// Structural smoke test only; this does not emulate Figma rendering or its API validation.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const nodes = [];
let finish;
const done = new Promise(resolve => { finish = resolve; });
function node(type) {
  const result = {
    id: String(nodes.length + 1), type, children: [], x: 0, y: 0,
    resize(w, h) { assert(w > 0 && h > 0); this.width = w; this.height = h; },
    appendChild(child) { this.children.push(child); child.parent = this; },
    async setReactionsAsync(reactions) { this.reactions = reactions; },
  };
  nodes.push(result);
  return result;
}
const context = {
  console,
  figma: {
    async listAvailableFontsAsync() { return ['Inter', 'Georgia'].map(family => ({ fontName: { family, style: 'Regular' } })); },
    async loadFontAsync() {},
    createFrame() { return node('FRAME'); },
    createText() { return node('TEXT'); },
    createPage() { return node('PAGE'); },
    async setCurrentPageAsync() {},
    viewport: { scrollAndZoomIntoView() {} },
    closePlugin(message) { finish(message); },
  },
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'code.js'), 'utf8'), context);
done.then(message => {
  assert.match(message, /^Created 76 editable frames/);
  const page = nodes.find(n => n.type === 'PAGE');
  const frames = page.children;
  assert.equal(frames.length, 76);
  assert.equal(new Set(frames.map(n => n.name)).size, 76);
  assert.equal(page.flowStartingPoints.length, 2);
  const ids = new Set(frames.map(n => n.id));
  const adjacency = new Map(frames.map(n => [n.id, []]));
  let connectionCount = 0;
  for (const n of nodes.filter(n => n.reactions)) {
    let root = n;
    while (root.parent && root.parent !== page) root = root.parent;
    assert(ids.has(root.id));
    for (const reaction of n.reactions) {
      assert.equal(reaction.trigger.type, 'ON_CLICK');
      for (const action of reaction.actions) {
        assert(ids.has(action.destinationId), 'Every link must target a generated frame');
        adjacency.get(root.id).push(action.destinationId);
        connectionCount++;
      }
    }
  }
  for (const start of page.flowStartingPoints) {
    const seen = new Set();
    const pending = [start.nodeId];
    while (pending.length) {
      const id = pending.pop();
      if (seen.has(id)) continue;
      seen.add(id);
      pending.push(...adjacency.get(id));
    }
    assert.equal(seen.size, 38, 'Each device flow must reach all 19 screens in both themes');
  }
  for (const n of nodes.filter(n => n.reactions)) {
    const parent = n.parent;
    assert(n.x >= 0 && n.y >= 0, 'Click targets must not begin outside their parent');
    assert(n.x + n.width <= parent.width + 1 && n.y + n.height <= parent.height + 1,
      `Click target outside parent: ${parent.name} / ${n.name}`);
  }
  console.log(`PASS: 76 frames, ${connectionCount} connections, two fully reachable flows, and click-target bounds.`);
  console.log('Not tested: actual Figma import, font rendering, or Present mode.');
}).catch(error => { console.error(error); process.exitCode = 1; });
