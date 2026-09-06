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

function matchesMarketTab(row, tab) {
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
  if (Number(cache.version || 0) !== 4) return {}
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

if (typeof module !== "undefined") {
  module.exports = {
    formatUsd: formatUsd,
    formatCompactNumber: formatCompactNumber,
    formatCompactUsd: formatCompactUsd,
    formatPercent: formatPercent,
    formatSignedUsd: formatSignedUsd,
    pnlColor: pnlColor,
    marketCategory: marketCategory,
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
