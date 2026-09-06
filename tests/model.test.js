const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.equal(Model.shouldHandleLoginStatus("logged-out", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("logged-out", false, true), true)
assert.equal(Model.shouldHandleLoginStatus("opening", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("opening", true, false), true)
assert.equal(Model.shouldHandleLoginStatus("done", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("done", true, false), true)

const detail = {
  id: "BTC",
  productId: "BTC-USD",
  period: "week",
  sparkline: [90, 100]
}
const detailCache = {
  entries: {
    "crypto|BTC-USD|BTC|week": { fetchedAt: 1, data: detail }
  }
}
assert.equal(Model.detailCacheKey({ id: "btc", productId: "btc-usd", kind: "crypto" }, "week"), "crypto|BTC-USD|BTC|week")
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "week"), detail)
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "day"), {})

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
