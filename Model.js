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

function parseSnapshot(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (data && typeof data === "object") return data
  } catch (e) {}
  return {}
}

function parseSearch(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    formatUsd: formatUsd,
    formatCompactNumber: formatCompactNumber,
    formatCompactUsd: formatCompactUsd,
    formatPercent: formatPercent,
    formatSignedUsd: formatSignedUsd,
    pnlColor: pnlColor,
    sparklineGeometry: sparklineGeometry,
    parseSnapshot: parseSnapshot,
    parseSearch: parseSearch,
    formatChartTime: formatChartTime
  }
}
