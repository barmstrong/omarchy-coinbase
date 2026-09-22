const assert = require("node:assert/strict")
const Model = require("../Model.js")
const panelSource = require("node:fs").readFileSync(require("node:path").join(__dirname, "../Panel.qml"), "utf8")
assert.doesNotMatch(panelSource, /updateHint|updateBusy/)
assert.match(panelSource, /Model\.shouldShowUpdating/)
assert.match(panelSource, /Waiting for data\. Retrying automatically…/)

const loaded = {hasData: true, hasChart: true, snapshotRunning: true, chartRunning: false, periodChange: false, detailPeriodChange: false, detailMissing: false}
assert.equal(Model.shouldShowUpdating(loaded), false, "opening with cached data stays quiet")
assert.equal(Model.shouldShowUpdating({...loaded, periodChange: true}), true, "period click gets immediate feedback")
assert.equal(Model.shouldShowUpdating({...loaded, hasData: false}), true, "missing data gets feedback")
assert.equal(Model.shouldShowUpdating({...loaded, hasChart: false}), true, "missing chart gets feedback")
assert.equal(Model.shouldShowUpdating({...loaded, chartRunning: true}), false, "background detail refresh stays quiet")
assert.equal(Model.shouldShowUpdating({...loaded, chartRunning: true, detailMissing: true}), true)
assert.equal(Model.shouldShowUpdating({...loaded, chartRunning: true, detailPeriodChange: true}), true)
assert.equal(Model.shouldShowUpdating({...loaded, snapshotRunning: false, periodChange: true}), false, "completed or failed process clears feedback")
assert.equal(Model.shouldShowUpdating({...loaded, snapshotRunning: false, chartRunning: false, detailPeriodChange: true}), false)

const selected = {kind: "crypto", productId: "BTC-USD"}
assert.equal(Model.selectionIndex([{kind: "crypto", productId: "ETH-USD"}, selected], Model.assetKey(selected), 0), 1)
assert.equal(Model.selectionIndex([], Model.assetKey(selected), 0), -1)
assert.equal(Model.selectionIndex([selected], "removed", 3), 0)
assert.equal(Model.selectionIndex([selected], "", -1), -1)
const now = Date.parse("2026-09-21T12:05:00Z")
assert.equal(Model.freshnessText({fetchedAt: "2026-09-21T12:00:00Z", error: "offline"}, now), "Last updated 5m ago · retrying automatically")
assert.equal(Model.freshnessText({fetchedAt: "2026-09-21T12:04:59Z"}, now), "")
assert.equal(Model.freshnessText({fetchedAt: "invalid", error: "offline"}, now), "Refresh failed · retrying automatically")

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
assert.equal(Model.formatCompactUsd(2163414), "$2.16M")
assert.equal(Model.formatCompactUsd(2083257), "$2.08M")
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
  version: 5,
  entries: {
    "crypto|BTC-USD|BTC|week": { fetchedAt: 1, data: detail }
  }
}
assert.equal(Model.detailCacheKey({ id: "btc", productId: "btc-usd", kind: "crypto" }, "week"), "crypto|BTC-USD|BTC|week")
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "week"), detail)
assert.deepEqual(Model.cachedDetail(detailCache, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "day"), {})
assert.deepEqual(Model.cachedDetail({ version: 4, entries: detailCache.entries }, { id: "BTC", productId: "BTC-USD", kind: "crypto" }, "week"), {})

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
