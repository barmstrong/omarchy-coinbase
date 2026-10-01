const assert = require("node:assert/strict")
const Model = require("../Model.js")
assert.equal(Model.watchlistIsWatched({}, {watchlist: true}), true, "cached membership avoids flashing an empty star on open")
assert.equal(Model.watchlistIsWatched({watched: false}, {watchlist: true}), false, "confirmed removal overrides the open asset's cached membership")
assert.equal(Model.watchlistIsWatched({watched: true}, {watchlist: false}), true)
assert.equal(Model.watchlistIsWatched({}, null), false)
const refA = {tokenCbrn: "v1:token:base:mainnet:0xa:"}
const refB = {equityCbrn: "v1:equity:::b:"}
const hiddenRef = {predictionCbrn: "v1:derivative:kalshi:event:hidden:"}
const hiddenRef2 = {ipoCbrn: "v1:equity:::hidden-ipo:"}
const watchRows = [
  {id: "A", kind: "crypto", watchlist: true, watchlistItem: refA, watchlistOrder: 0},
  {id: "B", kind: "stock", watchlist: true, watchlistItem: refB, watchlistOrder: 2}
]
const originalItems = [refA, hiddenRef, refB, hiddenRef2]
assert.equal(Model.watchlistMoveRequest(watchRows, 0, -1), null, "first visible row cannot move up")
assert.equal(Model.watchlistMoveRequest(watchRows, 1, 1), null, "last visible row cannot move down")
assert.equal(Model.watchlistMoveRequest(watchRows, -1, 1), null)
assert.equal(Model.watchlistMoveRequest(watchRows, 0, 2), null)
const dragRefs = Array.from({length: 6}, (_, i) => ({assetUuid: "drag-" + i}))
const dragRows = dragRefs.map(watchlistItem => ({watchlistItem}))
assert.deepEqual(Model.reorderedWatchlist(dragRefs, Model.watchlistMoveRequest(dragRows, 0, 5)),
  [...dragRefs.slice(1), dragRefs[0]], "drag from first to last in one request")
assert.deepEqual(Model.reorderedWatchlist(dragRefs, Model.watchlistMoveRequest(dragRows, 5, -5)),
  [dragRefs[5], ...dragRefs.slice(0, 5)], "drag from last to first")
assert.deepEqual(Model.reorderedWatchlist(dragRefs, Model.watchlistMoveRequest(dragRows, 1, 3)),
  [dragRefs[0], dragRefs[2], dragRefs[3], dragRefs[4], dragRefs[1], dragRefs[5]])
for (const [index, delta] of [[0, 0], [1.5, 1], [0, NaN], [0, 1.5], [0, 6], [5, -6]])
  assert.equal(Model.watchlistMoveRequest(dragRows, index, delta), null)
const moveUp = Model.watchlistMoveRequest(watchRows, 1, -1)
assert.deepEqual(moveUp, {item: refB, beforeItem: refA})
assert.deepEqual(Model.watchlistMoveRequest(watchRows, 0, 1), {item: refA, afterItem: refB})
const movedItems = Model.reorderedWatchlist(originalItems, moveUp)
assert.deepEqual(movedItems, [refB, refA, hiddenRef, hiddenRef2], "only the chosen item moves; hidden items keep relative order")
assert.deepEqual(originalItems, [refA, hiddenRef, refB, hiddenRef2], "optimistic move doesn't mutate saved data")
assert.deepEqual(Model.reorderedWatchlist(originalItems, {item: refA, afterItem: refB}), [hiddenRef, refB, refA, hiddenRef2])
assert.equal(Model.reorderedWatchlist(originalItems, {item: refA, beforeItem: refA}), null)
assert.equal(Model.reorderedWatchlist(originalItems, {item: refA, beforeItem: {assetUuid: "missing"}}), null)
const orderSnapshot = {assets: watchRows, watchlistStatus: {items: originalItems}}
const orderedSnapshot = Model.withWatchlistOrder(orderSnapshot, movedItems)
assert.equal(orderedSnapshot.assets[0].watchlistOrder, 1)
assert.equal(orderedSnapshot.assets[1].watchlistOrder, 0)
assert.equal(orderSnapshot.assets[0].watchlistOrder, 0)
const panelSource = require("node:fs").readFileSync(require("node:path").join(__dirname, "../Panel.qml"), "utf8")
const backArea = panelSource.slice(panelSource.indexOf("id: detailBackArea"), panelSource.indexOf("id: detailActions"))
assert.match(backArea, /visible: root.showingDetail/)
assert.match(backArea, /anchors.left: parent.left/)
assert.match(backArea, /anchors.right: detailActions.left/, "back target stops before Watchlist/Buy/Sell")
assert.match(backArea, /anchors.top: parent.top[\s\S]*anchors.bottom: parent.bottom/, "whole header height is clickable")
assert.match(backArea, /onClicked: root.closeDetail\(\)/)
assert.match(backArea, /Accessible.name: "Back to asset list"/)
const detailActions = panelSource.slice(panelSource.indexOf("id: detailActions"), panelSource.indexOf("id: accountActions"))
assert.match(detailActions, /id: watchlistButton[\s\S]*text: "Watchlist"[\s\S]*text: "Buy"[\s\S]*text: "Sell"/)
assert.match(detailActions, /iconText: Model\.watchlistIsWatched[^\n]*"★" : "☆"/)
const watchlistButton = detailActions.slice(detailActions.indexOf("id: watchlistButton"), detailActions.indexOf('text: "Buy"'))
assert.doesNotMatch(watchlistButton, /tooltipText|opacity:|watchlistActionProc.running/, "pending requests do not dim the button or change its tooltip/appearance")
assert.match(panelSource, /function toggleWatchlist\(\) \{[\s\S]*?if \(watchlistActionProc.running\) return/, "duplicate clicks are ignored without disabling the button")
assert.match(panelSource, /Model\.reconcileWatchlistState/, "failed state reads preserve the star")
assert.match(panelSource, /if \(!result.ok && root.watchlistBeforeAction\)/, "failed writes roll back the optimistic state")
assert.match(panelSource, /root\.watchlistMessage = result\.message \|\| \(result\.ok \? "" : "Could not confirm the watchlist update\."\)/)
assert.doesNotMatch(panelSource, /updateHint|updateBusy/)
assert.match(panelSource, /Model\.shouldShowUpdating/)
assert.match(panelSource, /Waiting for data\. Retrying automatically…/)

const loaded = {hasData: true, hasChart: true, snapshotRunning: true, chartRunning: false, periodChange: false, detailPeriodChange: false, detailMissing: false}

const beforeAdd = {watched: false, ready: true, canUpdate: true, item: {assetUuid: "test"}}
const adding = Model.optimisticWatchlistState(beforeAdd, "add")
assert.equal(adding.watched, true, "click fills the star before a request completes")
assert.equal(beforeAdd.watched, false, "saved rollback state is untouched")
assert.equal(Model.optimisticWatchlistState(adding, "remove").watched, false)
assert.equal(Model.reconcileWatchlistState(adding, {ok: false}).watched, true)
assert.equal(Model.reconcileWatchlistState(adding, {ok: true, ready: false, watched: false}).watched, true, "failed refresh doesn't reverse a successful write")
assert.equal(Model.reconcileWatchlistState(adding, {ok: true, ready: true, watched: false}).watched, false)

assert.equal(Model.pointerMoved(100, 200, 100, 200), false, "scrolling under a stationary pointer isn't mouse navigation")
assert.equal(Model.pointerMoved(100, 200, 102, 201), false, "ignore subpixel/rounding noise")
assert.equal(Model.pointerMoved(100, 200, 106, 200), true)
assert.equal(Model.pointerMoved(-1, -1, 100, 200), false, "initial hover doesn't override selection")
let scrollY = 0
for (let row = 0; row < 12; row++) {
  const next = Model.cursorScrollY(scrollY, 160, 664, row * 56, 48)
  assert.equal(next, Math.max(0, row - 2) * 56, "each step past the bottom reveals exactly one row")
  scrollY = next
}
assert.equal(Model.cursorScrollY(scrollY, 160, 664, 11 * 56, 48), scrollY, "last row doesn't wrap or scroll again")
assert.equal(Model.cursorScrollY(504, 160, 664, 8 * 56, 48), 448, "up past the top scrolls one row")
assert.equal(Model.cursorScrollY(20, 160, 80, 0, 48), 0, "short lists stay at the top")

// Exercise the actual panel navigation functions, with row-position events
// caused by scrolling while the physical pointer remains stationary.
const vm = require("node:vm")
// Exercise the actual QML action functions without any real API mutations.
const reorderProcess = {running: false}
const reordering = {Model, watchlistActionProc: reorderProcess, signedIn: true, watchlistReorderView: true,
  snapshot: orderSnapshot, watchlistOrderOverride: null, watchlistReorderMessage: "", listCursor: 1,
  ensureCursorVisible: () => {}, pluginFile: x => x}
reordering.root = reordering
Object.defineProperties(reordering, {
  watchlistStatus: {get: () => reordering.snapshot.watchlistStatus},
  visibleAssets: {get: () => reordering.snapshot.assets.slice().sort((a, b) => Model.watchlistRowOrder(a, reordering.watchlistOrderOverride) - Model.watchlistRowOrder(b, reordering.watchlistOrderOverride))},
  canReorderWatchlist: {get: () => !reorderProcess.running && reordering.watchlistOrderOverride === null}
})
for (const name of ["moveWatchlistItem", "finishWatchlistReorder"]) {
  const start = panelSource.indexOf("  function " + name + "(")
  vm.runInNewContext(panelSource.slice(start, panelSource.indexOf("\n  }", start) + 4), reordering)
}
reordering.moveWatchlistItem(1, -1)
assert.deepEqual(reordering.visibleAssets.map(row => row.id), ["B", "A"], "row moves before request finishes")
assert.equal(reordering.listCursor, 0, "selection follows moved item")
const firstPayload = reordering.watchlistPayload
reordering.moveWatchlistItem(0, 1)
assert.equal(reordering.watchlistPayload, firstPayload, "rapid duplicate input is ignored")
reordering.snapshot = {...orderSnapshot, assets: watchRows.map(row => ({...row, price: 777}))}
reordering.finishWatchlistReorder({ok: false, message: "offline"})
assert.deepEqual(reordering.visibleAssets.map(row => row.id), ["A", "B"])
assert.equal(reordering.listCursor, 1, "rollback keeps the same asset selected")
assert.equal(reordering.visibleAssets[0].price, 777, "rollback preserves concurrent price updates")
reorderProcess.running = false
reordering.moveWatchlistItem(1, -1)
reordering.finishWatchlistReorder({ok: true, message: "Refresh pending; do not repeat the action."})
assert.deepEqual(reordering.visibleAssets.map(row => row.id), ["B", "A"], "acknowledged move survives failed readback")
assert.notEqual(reordering.watchlistOrderOverride, null)
reordering.finishWatchlistReorder({ok: true, items: movedItems})
assert.equal(reordering.watchlistOrderOverride, null)
assert.deepEqual(reordering.visibleAssets.map(row => row.id), ["B", "A"], "server-confirmed order replaces optimistic state without a flicker")
assert.match(panelSource, /sequence: "Alt\+Up"/)
assert.match(panelSource, /sequence: "Alt\+Down"/)
const navigation = {Model, listCursor: 2, visibleAssets: Array(12).fill({}), hoverSelectEnabled: true, pointerX: 100, pointerY: 200, scrollY: 0}
navigation.root = navigation
navigation.ensureCursorVisible = () => {
  navigation.scrollY = Model.cursorScrollY(navigation.scrollY, 160, 664, navigation.listCursor * 56, 48)
  navigation.notePointerPosition({x: 100, y: 200})
  if (navigation.hoverSelectEnabled) navigation.listCursor = 0 // old row hover bug
}
for (const name of ["notePointerPosition", "moveListCursor", "moveListEdge"]) {
  const start = panelSource.indexOf("  function " + name + "(")
  const end = panelSource.indexOf("\n  }", start) + 4
  vm.runInNewContext(panelSource.slice(start, end), navigation)
}
for (let row = 3; row < 12; row++) {
  navigation.moveListCursor(1)
  assert.equal(navigation.listCursor, row)
  assert.equal(navigation.scrollY, (row - 2) * 56)
}
navigation.moveListEdge(false)
assert.equal(navigation.listCursor, 0)
assert.equal(navigation.scrollY, 0)
navigation.notePointerPosition({x: 107, y: 200})
assert.equal(navigation.hoverSelectEnabled, true, "real pointer movement restores hover navigation")
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
assert.equal(Model.snapshotNeedsRefresh({fetchedAt: new Date(now - 190 * 3600000).toISOString()}, now), true)
assert.equal(Model.snapshotNeedsRefresh({fetchedAt: new Date(now - 120000).toISOString()}, now), true)
assert.equal(Model.snapshotNeedsRefresh({fetchedAt: new Date(now - 119999).toISOString()}, now), false)
assert.equal(Model.snapshotNeedsRefresh({}, now), true)
// Opening even a fresh dashboard bypasses the cache; background polling
// coalesces recent work and reopening during a refresh doesn't launch another.
const snapshotProcess = {running: false, command: []}
const polling = {Model, snapshotProc: snapshotProcess, period: "day", opened: false,
  snapshot: {fetchedAt: new Date().toISOString()}, pendingSnapshotRaw: "", applySnapshotOnExit: false,
  snapshotFile: {reload: () => {}}, flick: {contentY: 0}, keyCatcher: {forceActiveFocus: () => {}},
  Qt: {callLater: fn => fn()}, pluginFile: x => x, syncTabToPin: () => {}}
polling.root = polling
for (const name of ["open", "refresh"]) {
  const start = panelSource.indexOf("  function " + name + "(")
  vm.runInNewContext(panelSource.slice(start, panelSource.indexOf("\n  }", start) + 4), polling)
}
polling.open("{}")
assert.equal(polling.opened, true)
assert.deepEqual(Array.from(snapshotProcess.command), ["bin/coinbase", "snapshot", "--period", "day"])
assert.equal(polling.applySnapshotOnExit, true, "an explicit open accepts the refreshed snapshot")
snapshotProcess.running = false
polling.refresh()
assert.deepEqual(Array.from(snapshotProcess.command), ["bin/coinbase", "snapshot", "--period", "day", "--max-age", "10"])
assert.equal(polling.applySnapshotOnExit, false, "background refresh preserves chart exploration")
const inFlightCommand = snapshotProcess.command
polling.open("{}")
assert.equal(snapshotProcess.command, inFlightCommand, "reopening shares the request in flight")
assert.equal(polling.applySnapshotOnExit, true)
assert.match(panelSource, /interval: Model.snapshotNeedsRefresh\(root.snapshot, root.statusNow\) \? 5000 : 15000/)

// Run the actual receive path: a stationary chart hover must not pin a
// days-old snapshot once the background refresh succeeds.
const freshSnapshot = {authenticated: true, assets: [], bar: {}, fetchedAt: new Date(now).toISOString(), error: ""}
const receiving = {Model, Date: {now: () => now}, opened: true, chartHover: true, snapshotReady: true,
  acceptSnapshotReload: false, lastSnapshotRaw: "", pendingSnapshotRaw: "",
  snapshot: {...freshSnapshot, fetchedAt: new Date(now - 190 * 3600000).toISOString(), error: "offline"}}
receiving.root = receiving
receiving.applySnapshot = (raw, parsed) => { receiving.snapshot = parsed; receiving.lastSnapshotRaw = raw; return true }
const receiveStart = panelSource.indexOf("  function receiveSnapshot(")
vm.runInNewContext(panelSource.slice(receiveStart, panelSource.indexOf("\n  }", receiveStart) + 4), receiving)
assert.equal(receiving.receiveSnapshot(JSON.stringify(freshSnapshot)), true)
assert.equal(receiving.snapshot.fetchedAt, freshSnapshot.fetchedAt)
assert.equal(receiving.pendingSnapshotRaw, "")
assert.equal(receiving.chartHover, false)
assert.equal(Model.freshnessText(receiving.snapshot, now), "", "successful recovery clears the warning")
receiving.chartHover = true
const newerSnapshot = {...freshSnapshot, fetchedAt: new Date(now + 1000).toISOString()}
receiving.receiveSnapshot(JSON.stringify(newerSnapshot))
assert.equal(receiving.pendingSnapshotRaw, JSON.stringify(newerSnapshot), "healthy chart exploration still defers background redraws")

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
const preipo = {id: "OPENAI", productId: "OPENAI-PERP-INTX", kind: "derivative", marketCategory: "preipo", watchlist: true}
const regular = {id: "NVDA", kind: "stock", marketCategory: "stock", watchlist: true}
assert.equal(Model.isVisibleAsset(preipo), false)
assert.equal(Model.isVisibleAsset(regular), true)
assert.equal(Model.matchesMarketTab(preipo, "all"), false)
assert.equal(Model.matchesMarketTab(preipo, "preipo"), false)
assert.doesNotMatch(panelSource, /label: "Pre-IPO"/)
// Exercise the actual panel filter: search bypasses tabs, but never eligibility.
const filtering = {Model, marketTab: "all", watchlistStatus: {source: "simple"}, searchResults: [], assetSearchScore: () => 1}
filtering.root = filtering
const filterStart = panelSource.indexOf("  function filteredAssets(")
vm.runInNewContext(panelSource.slice(filterStart, panelSource.indexOf("\n  }", filterStart) + 4), filtering)
for (const tab of ["all", "watchlist", "preipo"]) {
  filtering.marketTab = tab
  assert.equal(filtering.filteredAssets("", [preipo]).length, 0, "cached pre-IPO rows stay hidden in " + tab)
  filtering.searchResults = [preipo]
  assert.equal(filtering.filteredAssets("openai", [preipo]).length, 0, "both cached and fetched search hits stay hidden")
}
filtering.marketTab = "watchlist"
assert.equal(filtering.filteredAssets("", [regular])[0], regular, "supported watchlist rows remain visible")
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
