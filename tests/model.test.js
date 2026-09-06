const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.equal(Model.shouldHandleLoginStatus("logged-out", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("logged-out", false, true), true)
assert.equal(Model.shouldHandleLoginStatus("opening", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("opening", true, false), true)
assert.equal(Model.shouldHandleLoginStatus("done", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("done", true, false), true)

const cached = {
  authenticated: false,
  assets: [{ id: "BTC" }],
  bar: { symbol: "BTC", price: 100 }
}

assert.deepEqual(Model.parseSnapshot(JSON.stringify(cached), null), cached)
assert.equal(Model.parseSnapshot("", null), null)
assert.equal(Model.parseSnapshot("{", null), null)
assert.equal(Model.parseSnapshot("{}", null), null)
assert.equal(Model.parseSnapshot(JSON.stringify({ authenticated: false, assets: [] }), null), null)

console.log("snapshot model tests passed")
