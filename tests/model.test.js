const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.equal(Model.shouldHandleLoginStatus("logged-out", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("logged-out", false, true), true)
assert.equal(Model.shouldHandleLoginStatus("opening", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("opening", true, false), true)
assert.equal(Model.shouldHandleLoginStatus("done", false, false), false)
assert.equal(Model.shouldHandleLoginStatus("done", true, false), true)

assert.equal(Model.marketCategory({ kind: "crypto" }), "crypto")
assert.equal(Model.marketCategory({ kind: "derivative", marketCategory: "commodity" }), "commodity")
assert.equal(Model.marketCategory({ kind: "derivative", marketCategory: "preipo" }), "preipo")
assert.equal(Model.matchesMarketTab({ kind: "crypto", marketCategory: "crypto" }, "crypto"), true)
assert.equal(Model.matchesMarketTab({ kind: "derivative", marketCategory: "crypto" }, "crypto"), false)
assert.equal(Model.matchesMarketTab({ kind: "derivative", marketCategory: "crypto" }, "all"), true)
assert.equal(Model.shouldDefaultToWatchlist(true, true), false)
assert.equal(Model.shouldDefaultToWatchlist(true, false), true)
assert.equal(Model.shouldDefaultToWatchlist(false, true), true)
assert.equal(Model.marketVolume({ volume24h: 0, marketCap: 1000000 }), 0)
assert.equal(Model.marketVolume({ marketCap: 1000000 }), 0)
assert.equal(Model.formatCompactUsd(35505366427.55), "$35.51B")
assert.deepEqual(
  [
    { id: "LOW", volume24h: 10 },
    { id: "HIGH", volume24h: 100 },
    { id: "MID", volume24h: 50 }
  ].sort(Model.compareMarketVolume).map(function(row) { return row.id }),
  ["HIGH", "MID", "LOW"]
)

const detail = {
  id: "BTC",
  productId: "BTC-USD",
  period: "week",
  sparkline: [90, 100]
}
const detailCache = {
  version: 4,
  entries: {
    "crypto|BTC-USD|BTC|week": { fetchedAt: 1, data: detail }
  }
}
assert.equal(Model.detailCacheKey({ id: "btc", productId: "btc-usd", kind: "crypto" }, "week"), "crypto|BTC-USD|BTC|week")
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "week"), detail)
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "day"), {})
assert.deepEqual(Model.cachedDetail({ version: 3, entries: detailCache.entries }, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "week"), {})

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
