function isFiniteNumber(value) {
  var n = Number(value)
  return isFinite(n)
}

function formatUsd(value, decimals) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  if (decimals === undefined || decimals === null) decimals = Math.abs(n) >= 1000 ? 0 : 2
  var factor = Math.pow(10, decimals)
  var rounded = Math.round(n * factor) / factor
  var parts = Math.abs(rounded).toFixed(decimals).split(".")
  var grouped = parts[0]
  var out = ""
  while (grouped.length > 3) {
    out = "," + grouped.slice(-3) + out
    grouped = grouped.slice(0, -3)
  }
  var sign = rounded < 0 ? "-" : ""
  return sign + "$" + grouped + out + (parts[1] !== undefined ? "." + parts[1] : "")
}

function formatCompactNumber(value) {
  var n = Number(value)
  if (!isFinite(n) || n === 0) return "—"
  var abs = Math.abs(n)
  var sign = n < 0 ? "-" : ""
  if (abs >= 1e12) return sign + (abs / 1e12).toFixed(2) + "T"
  if (abs >= 1e9) return sign + (abs / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return sign + (abs / 1e6).toFixed(2) + "M"
  if (abs >= 1e3) return sign + (abs / 1e3).toFixed(abs >= 10000 ? 1 : 2) + "K"
  return sign + abs.toFixed(abs >= 100 ? 0 : 2)
}

function formatCompactUsd(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  var abs = Math.abs(n)
  var sign = n < 0 ? "-" : ""
  if (abs >= 1e12) return sign + "$" + (abs / 1e12).toFixed(2) + "T"
  if (abs >= 1e9) return sign + "$" + (abs / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return sign + "$" + (abs / 1e6).toFixed(abs >= 1e7 ? 1 : 2) + "M"
  if (abs >= 1000) return sign + "$" + (abs / 1000).toFixed(abs >= 10000 ? 1 : 2) + "k"
  return formatUsd(n, 2)
}

function formatPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  return (n > 0 ? "+" : "") + n.toFixed(2) + "%"
}

function formatSignedUsd(value, decimals) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  var text = formatUsd(n, decimals)
  if (n > 0) return "+" + text
  return text
}

function pnlColor(value, upColor, downColor, flatColor) {
  var n = Number(value)
  if (!isFinite(n) || n === 0) return flatColor
  return n > 0 ? upColor : downColor
}

function marketCategory(row) {
  row = row || {}
  var category = String(row.marketCategory || "").toLowerCase()
  if (["crypto", "stock", "commodity", "index", "preipo"].indexOf(category) !== -1)
    return category
  var kind = String(row.kind || "crypto").toLowerCase()
  if (kind === "stock") return "stock"
  if (kind === "commodity") return "commodity"
  return "crypto"
}

function isVisibleAsset(row) {
  // Manual exclusion until account-specific product eligibility is available.
  return !!row && marketCategory(row) !== "preipo"
}

function matchesMarketTab(row, tab) {
  if (!isVisibleAsset(row)) return false
  row = row || {}
  tab = String(tab || "all").toLowerCase()
  if (tab === "all") return String(row.kind || "").toLowerCase() !== "fiat"
  if (tab === "crypto")
    return marketCategory(row) === "crypto" && String(row.kind || "crypto").toLowerCase() === "crypto"
  return marketCategory(row) === tab
}

function shouldDefaultToWatchlist(opened, userSelectedTab) {
  return opened !== true || userSelectedTab !== true
}

function marketVolume(row) {
  row = row || {}
  var raw = row.volume24h
  if (raw === undefined || raw === null) raw = row.volume
  var value = Number(raw || 0)
  return isFinite(value) && value > 0 ? value : 0
}

function compareMarketVolume(a, b) {
  var delta = marketVolume(b) - marketVolume(a)
  if (delta !== 0) return delta
  return String((a && a.id) || "").localeCompare(String((b && b.id) || ""))
}

function sparklineGeometry(values, width, height) {
  var nums = []
  if (values) {
    for (var i = 0; i < values.length; i++) {
      var n = Number(values[i])
      if (isFinite(n)) nums.push(n)
    }
  }
  if (nums.length < 2 || width <= 2 || height <= 2)
    return { points: [], up: true, min: 0, max: 0, values: nums }

  var min = nums[0]
  var max = nums[0]
  for (var j = 1; j < nums.length; j++) {
    if (nums[j] < min) min = nums[j]
    if (nums[j] > max) max = nums[j]
  }
  var span = max - min
  if (span === 0) span = 1
  var pad = 2
  var innerH = Math.max(1, height - pad * 2)
  var dx = (width - 1) / (nums.length - 1)
  var points = []
  for (var k = 0; k < nums.length; k++) {
    points.push({
      x: k * dx,
      y: pad + innerH - ((nums[k] - min) / span) * innerH,
      value: nums[k]
    })
  }
  return { points: points, up: nums[nums.length - 1] >= nums[0], min: min, max: max, values: nums }
}

function formatChartTime(index, count, period) {
  var i = Number(index)
  var n = Number(count)
  if (!isFinite(i) || !isFinite(n) || i < 0 || n < 2) return ""
  var spans = { hour: 3600, day: 86400, week: 7 * 86400, month: 30 * 86400, year: 365 * 86400, all: 5 * 365 * 86400 }
  var span = spans[String(period || "day")] || 86400
  var t = Date.now() - (1 - i / (n - 1)) * span * 1000
  var d = new Date(t)
  var p = String(period || "day")
  if (p === "hour" || p === "day") return Qt.formatDateTime(d, "h:mm AP")
  if (p === "week") return Qt.formatDateTime(d, "ddd h:mm AP")
  if (p === "month") return Qt.formatDateTime(d, "MMM d h:mm AP")
  return Qt.formatDateTime(d, "MMM d yyyy")
}

function isSnapshot(data) {
  return !!data
    && typeof data === "object"
    && typeof data.authenticated === "boolean"
    && Array.isArray(data.assets)
    && !!data.bar
    && typeof data.bar === "object"
}

function parseSnapshot(raw, fallback) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (isSnapshot(data)) return data
  } catch (e) {}
  return fallback === undefined ? {} : fallback
}

function parseSearch(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function shouldHandleLoginStatus(status, signingIn, signedIn) {
  var current = String(status || "")
  if (["opening", "waiting", "exchanging", "snapshot", "done", "error"].indexOf(current) !== -1)
    return signingIn === true
  if (current === "logged-out") return signedIn === true || signingIn === true
  return false
}

function detailCacheKey(row, period) {
  row = row || {}
  return [
    String(row.kind || "crypto").trim().toLowerCase(),
    String(row.productId || row.id || "").trim().toUpperCase(),
    String(row.id || "").trim().toUpperCase(),
    String(period || "day").trim().toLowerCase()
  ].join("|")
}

function cachedDetail(cache, row, period) {
  if (!cache || typeof cache !== "object" || !row) return {}
  if (Number(cache.version || 0) !== 5) return {}
  var entries = cache.entries
  if (!entries || typeof entries !== "object") return {}
  var entry = entries[detailCacheKey(row, period)]
  var data = entry && entry.data
  if (!data || typeof data !== "object" || !Array.isArray(data.sparkline) || data.sparkline.length < 2)
    return {}
  var wanted = String(row.productId || row.id || "").toUpperCase()
  var got = String(data.productId || data.id || "").toUpperCase()
  if (wanted && got && got !== wanted && got.split("-")[0] !== wanted.split("-")[0]) return {}
  if (String(data.period || "day") !== String(period || "day")) return {}
  return data
}

function shouldShowUpdating(state) {
  // Cached content stays quiet on open and on timer-driven refreshes.
  // An explicit period change or a missing part of the view needs feedback.
  return (state.snapshotRunning && (state.periodChange || !state.hasData || !state.hasChart))
    || (state.chartRunning && (state.detailPeriodChange || !state.hasChart || state.detailMissing))
}

function watchlistIsWatched(state, row) {
  return typeof state.watched === "boolean" ? state.watched : !!(row && row.watchlist)
}

function optimisticWatchlistState(state, action) {
  return Object.assign({}, state, {watched: action === "add"})
}

function reconcileWatchlistState(previous, result) {
  if (!result.ok) return previous
  // A failed read-after-write must not undo an acknowledged mutation.
  return result.ready ? result : Object.assign({}, result, {watched: previous.watched})
}

function assetKey(row) {
  return row ? String(row.kind || "crypto") + ":" + String(row.productId || row.id || "").toUpperCase() : ""
}

function selectionIndex(rows, key, previousIndex) {
  if (previousIndex < 0) return -1
  for (var i = 0; i < rows.length; i++) {
    if (assetKey(rows[i]) === key) return i
  }
  return Math.min(previousIndex, rows.length - 1)
}

function pointerMoved(previousX, previousY, x, y) {
  return previousX >= 0 && previousY >= 0 && isFinite(x) && isFinite(y)
    && (Math.abs(x - previousX) > 4 || Math.abs(y - previousY) > 4)
}

function cursorScrollY(currentY, viewHeight, contentHeight, rowTop, rowHeight) {
  var next = currentY
  if (rowTop < currentY) next = rowTop
  else if (rowTop + rowHeight > currentY + viewHeight)
    next = rowTop + rowHeight - viewHeight
  return Math.max(0, Math.min(Math.max(0, contentHeight - viewHeight), next))
}

function watchlistItemKey(item) {
  if (!item || typeof item !== "object") return ""
  var fields = Object.keys(item)
  if (fields.length !== 1 || typeof item[fields[0]] !== "string" || !item[fields[0]]) return ""
  return fields[0] + ":" + item[fields[0]]
}

function watchlistMoveRequest(rows, index, delta) {
  if (delta !== -1 && delta !== 1) return null
  if (index < 0 || index >= rows.length || index + delta < 0 || index + delta >= rows.length) return null
  var item = rows[index].watchlistItem
  var anchor = rows[index + delta].watchlistItem
  if (!watchlistItemKey(item) || !watchlistItemKey(anchor) || watchlistItemKey(item) === watchlistItemKey(anchor)) return null
  var body = {item: item}
  body[delta < 0 ? "beforeItem" : "afterItem"] = anchor
  return body
}

function reorderedWatchlist(items, request) {
  var result = (items || []).slice()
  if (!request) return null
  var itemKey = watchlistItemKey(request.item)
  var anchorKey = watchlistItemKey(request.beforeItem || request.afterItem)
  var from = -1, anchor = -1
  for (var i = 0; i < result.length; i++) {
    if (watchlistItemKey(result[i]) === itemKey) from = i
    if (watchlistItemKey(result[i]) === anchorKey) anchor = i
  }
  if (from < 0 || anchor < 0 || from === anchor) return null
  var moved = result.splice(from, 1)[0]
  if (from < anchor) anchor--
  result.splice(anchor + (request.afterItem ? 1 : 0), 0, moved)
  return result
}

function watchlistRowOrder(row, items) {
  if (items) {
    var key = watchlistItemKey(row.watchlistItem)
    for (var i = 0; i < items.length; i++)
      if (key && watchlistItemKey(items[i]) === key) return i
  }
  var order = Number(row.watchlistOrder)
  return isFinite(order) ? order : 1e9
}

function withWatchlistOrder(snapshot, items) {
  var next = Object.assign({}, snapshot)
  next.watchlistStatus = Object.assign({}, snapshot.watchlistStatus, {items: items})
  next.assets = (snapshot.assets || []).map(function(row) {
    return row.watchlist ? Object.assign({}, row, {watchlistOrder: watchlistRowOrder(row, items)}) : row
  })
  return next
}

function snapshotNeedsRefresh(snapshot, now) {
  var stamp = Date.parse((snapshot || {}).fetchedAt || "")
  return !isFinite(stamp) || now - stamp >= 120000
}

function freshnessText(snapshot, now) {
  var stamp = Date.parse(snapshot.fetchedAt || "")
  var failed = !!snapshot.error
  if (!isFinite(stamp)) return failed ? "Refresh failed · retrying automatically" : ""
  var seconds = Math.max(0, (now - stamp) / 1000)
  if (!failed && seconds < 120) return ""
  var age = seconds < 60 ? "just now" : (seconds < 3600 ? Math.floor(seconds / 60) + "m ago" : Math.floor(seconds / 3600) + "h ago")
  return "Last updated " + age + (failed ? " · retrying automatically" : " · data may be stale")
}

if (typeof module !== "undefined") {
  module.exports = {
    shouldShowUpdating: shouldShowUpdating,
    watchlistIsWatched: watchlistIsWatched,
    optimisticWatchlistState: optimisticWatchlistState,
    reconcileWatchlistState: reconcileWatchlistState,
    assetKey: assetKey,
    selectionIndex: selectionIndex,
    pointerMoved: pointerMoved,
    cursorScrollY: cursorScrollY,
    freshnessText: freshnessText,
    snapshotNeedsRefresh: snapshotNeedsRefresh,
    watchlistItemKey: watchlistItemKey,
    watchlistMoveRequest: watchlistMoveRequest,
    reorderedWatchlist: reorderedWatchlist,
    watchlistRowOrder: watchlistRowOrder,
    withWatchlistOrder: withWatchlistOrder,
    formatUsd: formatUsd,
    formatCompactNumber: formatCompactNumber,
    formatCompactUsd: formatCompactUsd,
    formatPercent: formatPercent,
    formatSignedUsd: formatSignedUsd,
    pnlColor: pnlColor,
    marketCategory: marketCategory,
    isVisibleAsset: isVisibleAsset,
    matchesMarketTab: matchesMarketTab,
    shouldDefaultToWatchlist: shouldDefaultToWatchlist,
    marketVolume: marketVolume,
    compareMarketVolume: compareMarketVolume,
    sparklineGeometry: sparklineGeometry,
    isSnapshot: isSnapshot,
    parseSnapshot: parseSnapshot,
    parseSearch: parseSearch,
    shouldHandleLoginStatus: shouldHandleLoginStatus,
    detailCacheKey: detailCacheKey,
    cachedDetail: cachedDetail,
    formatChartTime: formatChartTime
  }
}
