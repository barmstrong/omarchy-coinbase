import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var snapshot: ({})
  property bool snapshotReady: false
  property string lastSnapshotRaw: ""
  property string pendingSnapshotRaw: ""
  property bool acceptSnapshotReload: false
  property bool applySnapshotOnExit: false
  property bool refreshing: false
  property bool signingIn: false
  property string loginStatus: ""
  property string searchQuery: ""
  property var searchResults: []
  property string clientIdDraft: ""
  property string clientSecretDraft: ""
  property int listCursor: -1
  property string marketTab: "all"
  property bool marketTabUserSelected: false
  property bool hoverSelectEnabled: false
  property bool tabSynced: false
  property var detailAsset: null
  property var detailChart: ({})
  property var detailCache: ({})
  property bool detailLoading: false
  property var lastPortfolio: ({})
  property int chartSeq: 0
  property int chartProcSeq: 0
  property string chartWantId: ""
  property bool rowsRefreshPending: false
  property bool watchlistRefreshPending: false

  readonly property bool signedIn: snapshot.authenticated === true
  readonly property bool authLoading: root.signedIn && snapshot.loading === true
  readonly property bool needsSetup: snapshot.needsSetup === true
  readonly property color foreground: Color.popups.text
  readonly property color muted: Color.muted
  readonly property string fontFamily: Style.font.family
  readonly property int pad: Style.space(16)
  readonly property var periodOptions: [
    { value: "hour", label: "1H" },
    { value: "day", label: "1D" },
    { value: "week", label: "1W" },
    { value: "month", label: "1M" },
    { value: "year", label: "1Y" },
    { value: "all", label: "ALL" }
  ]
  readonly property var marketTabs: root.signedIn
    ? [
        { value: "watchlist", label: "Watchlist" },
        { value: "all", label: "All" },
        { value: "crypto", label: "Crypto" },
        { value: "stock", label: "Stocks" },
        { value: "commodity", label: "Commodities" },
        { value: "index", label: "Indices" },
        { value: "preipo", label: "Pre-IPO" }
      ]
    : [
        { value: "all", label: "All" },
        { value: "crypto", label: "Crypto" },
        { value: "stock", label: "Stocks" },
        { value: "commodity", label: "Commodities" },
        { value: "index", label: "Indices" },
        { value: "preipo", label: "Pre-IPO" }
      ]
  readonly property bool showingDetail: detailAsset !== null
  readonly property string period: String(snapshot.period || "day")
  readonly property var assets: snapshot.assets || []
  readonly property bool searching: String(searchQuery).replace(/^\s+|\s+$/g, "").length > 0
  readonly property var visibleAssets: filteredAssets(searchQuery, assets)
  readonly property real pnl: Number(root.showingDetail ? snapshot.pnl : root.portfolioField("pnl", snapshot.pnl))
  readonly property color pnlColor: Model.pnlColor(root.showingDetail ? Number((detailChart && detailChart.pnl) || (detailAsset && detailAsset.pnl) || 0) : pnl, Color.accent, Color.urgent, foreground)
  readonly property var sparkline: {
    if (root.showingDetail) {
      if (detailChart && detailChart.sparkline && detailChart.sparkline.length)
        return detailChart.sparkline
      if (detailAsset && detailAsset.rowSpark && detailAsset.rowSpark.length)
        return detailAsset.rowSpark
    }
    if (root.signedIn && root.portfolioLooksWrong(snapshot) && lastPortfolio && lastPortfolio.sparkline && lastPortfolio.sparkline.length)
      return lastPortfolio.sparkline
    return snapshot.sparkline || []
  }
  property bool chartHover: false
  property real chartHoverPrice: NaN
  property int chartHoverIndex: -1
  readonly property string chartHoverTime: {
    var n = sparkline.length
    var i = chartHoverIndex
    if (!root.chartHover || i < 0 || n < 2) return ""
    var spans = { hour: 3600, day: 86400, week: 7 * 86400, month: 30 * 86400, year: 365 * 86400, all: 5 * 365 * 86400 }
    var span = spans[period] || 86400
    var t = new Date(Date.now() - (1 - i / (n - 1)) * span * 1000)
    if (period === "hour" || period === "day") return Qt.formatDateTime(t, "h:mm AP")
    if (period === "week") return Qt.formatDateTime(t, "ddd h:mm AP")
    if (period === "month") return Qt.formatDateTime(t, "MMM d h:mm AP")
    return Qt.formatDateTime(t, "MMM d yyyy")
  }
  readonly property real displayPrice: {
    if (chartHover && isFinite(chartHoverPrice)) return chartHoverPrice
    if (root.showingDetail) {
      if (detailChart && isFinite(Number(detailChart.price)) && Number(detailChart.price) > 0)
        return Number(detailChart.price)
      return Number(detailAsset && detailAsset.price)
    }
    if (root.signedIn) return Number(root.portfolioField("total", snapshot.total))
    return Number(snapshot.bar && snapshot.bar.price)
  }
  readonly property real displayPnl: {
    if (!chartHover || !isFinite(chartHoverPrice) || !sparkline.length) {
      if (root.showingDetail) return Number((detailChart && detailChart.pnl) || (detailAsset && detailAsset.pnl) || 0)
      return Number(root.portfolioField("pnl", snapshot.pnl))
    }
    var start = Number(sparkline[0])
    if (!isFinite(start)) return Number(root.portfolioField("pnl", snapshot.pnl))
    return chartHoverPrice - start
  }
  readonly property real displayPnlPercent: {
    if (!chartHover || !isFinite(chartHoverPrice) || !sparkline.length) {
      if (root.showingDetail) return Number((detailChart && detailChart.pnlPercent) || (detailAsset && detailAsset.pnlPercent) || 0)
      return Number(root.portfolioField("pnlPercent", snapshot.pnlPercent))
    }
    var start = Number(sparkline[0])
    if (!isFinite(start) || start === 0) return Number(root.portfolioField("pnlPercent", snapshot.pnlPercent))
    return (chartHoverPrice - start) / start * 100
  }
  readonly property var barPnl: snapshot.bar || ({})
  readonly property string selectedAssetName: String(barPnl.name || "").trim()
  readonly property string selectedAssetSymbol: String(barPnl.symbol || "BTC").trim()
  readonly property string selectedAssetLabel: {
    if (selectedAssetName !== "" && selectedAssetName.toUpperCase() !== selectedAssetSymbol.toUpperCase())
      return selectedAssetName + " (" + selectedAssetSymbol + ")"
    return selectedAssetName || selectedAssetSymbol
  }
  readonly property var actions: snapshot.actions || ({
    send: "https://www.coinbase.com/send",
    receive: "https://www.coinbase.com/receive",
    deposit: "https://www.coinbase.com/deposit",
    withdraw: "https://www.coinbase.com/withdraw"
  })

  function pluginFile(rel) {
    var url = String(Qt.resolvedUrl(rel))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url
  }

  function receiveSnapshot(raw) {
    var serialized = String(raw || "")
    if (serialized !== "" && serialized === root.lastSnapshotRaw) {
      root.acceptSnapshotReload = false
      return true
    }
    var next = Model.parseSnapshot(serialized, null)
    if (!next) return false
    if (root.opened && root.snapshotReady && !root.acceptSnapshotReload) {
      root.pendingSnapshotRaw = serialized
      return true
    }
    root.acceptSnapshotReload = false
    root.pendingSnapshotRaw = ""
    return root.applySnapshot(serialized, next)
  }

  function applySnapshot(raw, parsed) {
    var serialized = String(raw || "")
    var next = parsed || Model.parseSnapshot(serialized, null)
    if (!next) return false
    root.lastSnapshotRaw = serialized
    var wasSigned = root.signedIn
    snapshot = next
    root.snapshotReady = true
    root.capturePortfolio(snapshot)
    if (root.signedIn && !wasSigned) {
      if (Model.shouldDefaultToWatchlist(root.opened, root.marketTabUserSelected))
        root.marketTab = "watchlist"
      root.tabSynced = true
      return true
    }
    if (!root.signedIn && wasSigned) {
      root.resetSignedOutView()
      return true
    }
    if (root.opened && !root.tabSynced && !root.marketTabUserSelected) {
      root.syncTabToPin()
      root.tabSynced = true
    }
    return true
  }

  function resetSignedOutView() {
    root.marketTab = "all"
    root.marketTabUserSelected = false
    root.tabSynced = true
    root.watchlistRefreshPending = false
    root.rowsRefreshPending = true
    root.searchQuery = ""
    root.searchResults = []
    root.listCursor = 0
    root.lastPortfolio = ({})
    if (searchField) searchField.text = ""
    root.closeDetail()
    if (flick) flick.contentY = 0
  }

  function publicCachedRows(rows) {
    var out = []
    rows = rows || []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || row.market !== true || String(row.kind || "") === "fiat") continue
      out.push({
        id: row.id,
        name: row.name,
        kind: row.kind,
        productId: row.productId,
        price: row.price,
        quantity: 0,
        value: 0,
        held: false,
        market: true,
        watchlist: false,
        marketCap: row.marketCap,
        marketCategory: row.marketCategory,
        volume24h: row.volume24h,
        costBasis: 0,
        unrealizedPnl: 0,
        dayPnl: row.dayPnl,
        dayPnlPercent: row.dayPnlPercent,
        pnl: row.pnl,
        pnlPercent: row.pnlPercent,
        url: row.url,
        buyUrl: row.buyUrl,
        sellUrl: row.sellUrl,
        rowSpark: row.rowSpark || [],
        rowSparkPeriod: row.rowSparkPeriod || "",
        rowSparkCache: row.rowSparkCache || ({}),
        yahoo: row.yahoo || ""
      })
    }
    return out
  }

  function leadPublicAsset(rows) {
    rows = rows || []
    for (var i = 0; i < rows.length; i++)
      if (String(rows[i].kind || "") === "crypto" && String(rows[i].id || "").toUpperCase() === "BTC") return rows[i]
    return rows.length ? rows[0] : null
  }

  function capturePortfolio(snap) {
    if (!snap || snap.authenticated !== true) return
    if (root.portfolioLooksWrong(snap)) return
    var s = snap.sparkline || []
    var total = Number(snap.total)
    if (!isFinite(total) || total <= 0 || s.length < 2) return
    lastPortfolio = {
      sparkline: s,
      total: total,
      pnl: Number(snap.pnl),
      pnlPercent: Number(snap.pnlPercent)
    }
  }

  function portfolioLooksWrong(snap) {
    if (!snap || !lastPortfolio || !lastPortfolio.total) return false
    var ref = Number(lastPortfolio.total)
    var total = Number(snap.total)
    var s = snap.sparkline || []
    var last = Number(s.length ? s[s.length - 1] : 0)
    if (isFinite(total) && total > 0 && total < ref * 0.05) return true
    if (s.length >= 2 && isFinite(last) && last > 0 && last < ref * 0.05) return true
    if (s.length >= 2 && isFinite(last) && isFinite(total) && total > 0 && Math.abs(last - total) / total > 0.35) return true
    return false
  }

  function portfolioField(key, fallback) {
    if (root.signedIn && root.portfolioLooksWrong(snapshot) && lastPortfolio && lastPortfolio[key] !== undefined)
      return lastPortfolio[key]
    return fallback
  }

  function syncTabToPin() {
    if (root.signedIn) {
      root.marketTab = "watchlist"
      return
    }
    root.marketTab = "all"
  }

  property real pointerX: -1
  property real pointerY: -1

  function notePointerMove(handler) {
    var pos = handler && handler.point ? handler.point.position : null
    if (!pos) {
      root.hoverSelectEnabled = true
      return
    }
    var x = pos.x
    var y = pos.y
    if (root.pointerX >= 0 && (Math.abs(x - root.pointerX) > 4 || Math.abs(y - root.pointerY) > 4))
      root.hoverSelectEnabled = true
    root.pointerX = x
    root.pointerY = y
  }

  function resetHoverSelect() {
    root.hoverSelectEnabled = false
    root.pointerX = -1
    root.pointerY = -1
    root.listCursor = root.visibleAssets.length > 0 ? 0 : -1
  }

  function assetSearchScore(row, q) {
    q = String(q || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (!q) return 0
    var id = String(row.id || "").toLowerCase()
    var name = String(row.name || "").toLowerCase()
    var product = String(row.productId || "").toLowerCase()
    var haystack = id + " " + name + " " + product
    var terms = q.split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
      if (terms[i] && haystack.indexOf(terms[i]) === -1) return 0
    }
    if (id === q) return 100
    if (name === q) return 90
    if (id.startsWith(q)) return 80
    if (name.startsWith(q)) return 60
    return 20 + terms.length * 5
  }

  function rowPeriodPercent(row) {
    if (!row || String(row.rowSparkPeriod || "") !== root.period) return NaN
    var values = row.rowSpark || []
    if (values.length < 2) return NaN
    var first = Number(values[0])
    var last = Number(values[values.length - 1])
    if (!isFinite(first) || !isFinite(last) || first === 0) return NaN
    return (last - first) / first * 100
  }

  function rowPeriodColor(row) {
    return Model.pnlColor(root.rowPeriodPercent(row), Color.accent, Color.urgent, root.muted)
  }

  function marketTypeLabel(row) {
    var category = Model.marketCategory(row)
    var labels = { crypto: "crypto", stock: "stock", commodity: "commodity", index: "index", preipo: "pre-IPO" }
    var label = labels[category] || category
    return String(row && row.kind || "") === "derivative" ? label + " perp" : label
  }

  function rowsNeedRefresh() {
    var rows = root.visibleAssets || []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || !row.productId || String(row.kind || "") === "fiat") continue
      if (Number(row.rowSparkVersion || 0) !== 2
          || String(row.rowSparkPeriod || "") !== root.period
          || (row.rowSpark || []).length < 2)
        return true
    }
    return false
  }

  function refreshRows(force) {
    if (!root.opened) return
    if (snapshotProc.running || rowProc.running) {
      root.rowsRefreshPending = true
      return
    }
    if (!force && !root.rowsNeedRefresh()) return
    root.rowsRefreshPending = false
    rowProc.command = [pluginFile("bin/coinbase"), "rows", "--period", root.period, "--tab", root.marketTab]
    rowProc.running = true
  }

  function filteredAssets(query, rows) {
    var q = String(query || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    rows = rows || []
    var out = []
    var tab = String(root.marketTab || "all")
    var seen = {}
    var searching = q.length > 0
    for (var i = 0; i < rows.length; i++) {
      var a = rows[i]
      var aid = String(a.id || "")
      var aname = String(a.name || "")
      if (!aid.replace(/^\s+|\s+$/g, "") && !aname.replace(/^\s+|\s+$/g, "")) continue
      var junk = aid.indexOf("v1:equity") === 0 || (aid.length >= 16 && /^[01]+$/.test(aid))
      if (junk && (aname === aid || aname === "Stock")) continue
      if (!searching) {
        if (tab === "watchlist") {
          if (!a.watchlist) continue
        } else if (!Model.matchesMarketTab(a, tab)) continue
      }
      if (q && root.assetSearchScore(a, q) <= 0) continue
      out.push(a)
      seen[String(a.kind || "") + ":" + String(a.id || "").toUpperCase()] = true
    }
    if (q.length >= 2) {
      var extra = root.searchResults || []
      for (var j = 0; j < extra.length; j++) {
        var hit = extra[j]
        var hid = String(hit.kind || "crypto") + ":" + String(hit.id || "").toUpperCase()
        if (seen[hid]) continue
        if (root.assetSearchScore(hit, q) <= 0) continue
        out.push(hit)
        seen[hid] = true
      }
    }
    if (q) {
      out.sort(function(a, b) {
        var d = root.assetSearchScore(b, q) - root.assetSearchScore(a, q)
        if (d !== 0) return d
        var volume = Model.marketVolume(b) - Model.marketVolume(a)
        if (volume !== 0) return volume
        return String(a.id || "").localeCompare(String(b.id || ""))
      })
    } else if (tab === "watchlist") {
      out.sort(function(a, b) {
        var ao = Number(a.watchlistOrder)
        var bo = Number(b.watchlistOrder)
        if (!isFinite(ao)) ao = 1e9
        if (!isFinite(bo)) bo = 1e9
        if (ao !== bo) return ao - bo
        return String(a.id || "").localeCompare(String(b.id || ""))
      })
    } else out.sort(Model.compareMarketVolume)
    return out
  }

  function open(payloadJson) {
    if (root.pendingSnapshotRaw !== "") {
      var pending = root.pendingSnapshotRaw
      root.pendingSnapshotRaw = ""
      root.applySnapshot(pending)
    }
    opened = true
    marketTabUserSelected = false
    watchlistRefreshPending = true
    listCursor = 0
    hoverSelectEnabled = false
    tabSynced = false
    if (flick) flick.contentY = 0
    snapshotFile.reload()
    syncTabToPin()
    refresh()
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function focusSearch() {
    if (root.showingDetail) return
    searchField.forceActiveFocus()
    searchField.selectAll()
    if (listCursor < 0 && visibleAssets.length > 0) listCursor = 0
  }

  function moveListCursor(delta) {
    if (visibleAssets.length === 0) {
      listCursor = -1
      return
    }
    var next = listCursor + delta
    if (listCursor < 0) next = delta > 0 ? 0 : visibleAssets.length - 1
    if (next < 0) next = 0
    if (next > visibleAssets.length - 1) next = visibleAssets.length - 1
    listCursor = next
    root.ensureCursorVisible()
  }

  function moveListEdge(toEnd) {
    if (visibleAssets.length === 0) {
      listCursor = -1
      return
    }
    listCursor = toEnd ? visibleAssets.length - 1 : 0
    root.ensureCursorVisible()
  }

  function ensureCursorVisible() {
    Qt.callLater(function() {
      if (root.listCursor < 0) return
      var view = root.searching ? overlayFlick : flick
      var repeater = root.searching ? searchAssetRepeater : marketAssetRepeater
      var item = repeater.itemAt(root.listCursor)
      if (!view || !item) return
      var mapped = item.mapToItem(view.contentItem, 0, 0)
      var top = mapped.y
      var bottom = top + item.height
      if (top < view.contentY)
        view.contentY = Math.max(0, top)
      else if (bottom > view.contentY + view.height)
        view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), bottom - view.height)
    })
  }

  function moveTab(delta) {
    if (root.showingDetail || root.searching || !root.marketTabs.length) return
    var current = 0
    for (var i = 0; i < root.marketTabs.length; i++) {
      if (root.marketTabs[i].value === root.marketTab) {
        current = i
        break
      }
    }
    var next = (current + delta + root.marketTabs.length) % root.marketTabs.length
    root.marketTabUserSelected = true
    root.tabSynced = true
    root.marketTab = root.marketTabs[next].value
    root.resetHoverSelect()
    if (flick) flick.contentY = 0
    Qt.callLater(function() { root.refreshRows(false) })
  }

  function isBarAsset(row) {
    if (!row) return false
    var pid = String(barPnl.productId || "").toUpperCase()
    var rowPid = String(row.productId || "").toUpperCase()
    if (pid && rowPid) return rowPid === pid
    var sym = String(barPnl.symbol || "").toUpperCase()
    return !!(sym && String(row.id || "").toUpperCase() === sym && String(row.kind || "") === String(barPnl.kind || "crypto"))
  }

  function tickerId(row) {
    if (!row) return ""
    return String(row.productId || row.id || "")
  }

  function setBarTicker(productId, symbol) {
    if (!productId || root.signedIn) return
    if (tickerProc.running) tickerProc.running = false
    var cmd = [pluginFile("bin/coinbase"), "ticker", productId]
    if (symbol) cmd.push("--symbol", String(symbol))
    tickerProc.command = cmd
    tickerProc.running = true
    if (!root.signedIn) refreshing = true
  }

  function pinToBar(row) {
    if (!row || root.signedIn) return
    var price = Number(row.price) || 0
    var values = row.rowSpark || []
    var start = Number(values.length ? values[0] : price)
    var pnl = isFinite(start) ? price - start : 0
    var pct = isFinite(root.rowPeriodPercent(row)) ? root.rowPeriodPercent(row) : Number(row.pnlPercent || 0)
    var next = Object.assign({}, root.snapshot)
    next.total = price
    next.pnl = pnl
    next.pnlPercent = pct
    next.sparkline = values
    next.bar = {
      pnl: pnl,
      pnlPercent: pct,
      period: root.period,
      symbol: String(row.id || ""),
      productId: root.tickerId(row),
      name: String(row.name || row.id || ""),
      kind: String(row.kind || "crypto"),
      price: price
    }
    root.snapshot = next
    root.setBarTicker(root.tickerId(row), String(row.id || ""))
  }

  function chooseAsset(row) {
    if (!row) return
    root.openDetail(row)
  }

  function openDetail(row) {
    if (!row) return
    root.detailAsset = row
    searchDebounce.stop()
    if (searchProc.running) searchProc.running = false
    root.searchQuery = ""
    root.searchResults = []
    if (searchField) searchField.text = ""
    root.loadDetailChart(row)
    Qt.callLater(function() {
      if (root.showingDetail && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function loadDetailChart(row, periodOverride) {
    if (!row) return
    root.chartSeq += 1
    root.chartProcSeq = root.chartSeq
    root.chartWantId = String(root.tickerId(row) || "").toUpperCase()
    if (chartProc.running) chartProc.running = false
    root.detailLoading = true
    var p = periodOverride || period
    root.detailChart = Model.cachedDetail(root.detailCache, row, p)
    chartProc.command = [pluginFile("bin/coinbase"), "chart", root.tickerId(row), "--period", p, "--symbol", String(row.id || ""), "--kind", String(row.kind || "crypto")]
    chartProc.running = true
  }

  function closeDetail() {
    root.chartSeq += 1
    if (chartProc.running) chartProc.running = false
    root.detailAsset = null
    root.detailChart = ({})
    root.detailLoading = false
    root.chartHover = false
    root.chartHoverPrice = NaN
    root.chartHoverIndex = -1
  }

  function activateCursor() {
    if (visibleAssets.length === 0) return
    var idx = listCursor
    if (idx < 0 || idx >= visibleAssets.length) idx = 0
    listCursor = idx
    root.chooseAsset(visibleAssets[idx])
  }

  function close() {
    opened = false
    watchlistRefreshPending = false
    signingIn = false
    closeDetail()
    if (root.pendingSnapshotRaw !== "") {
      var pending = root.pendingSnapshotRaw
      root.pendingSnapshotRaw = ""
      root.applySnapshot(pending)
    }
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "coinbase")
    else close()
  }

  function refresh(force) {
    if (snapshotProc.running) {
      if (force === true) root.applySnapshotOnExit = true
      return
    }
    refreshing = true
    root.applySnapshotOnExit = force === true
    snapshotProc.command = [pluginFile("bin/coinbase"), "snapshot", "--period", period]
    if (!force) snapshotProc.command.push("--max-age", "20")
    snapshotProc.running = true
  }

  function refreshWatchlist() {
    if (!root.opened || !root.signedIn) return
    if (snapshotProc.running || watchlistProc.running) {
      root.watchlistRefreshPending = true
      return
    }
    root.watchlistRefreshPending = false
    watchlistProc.command = [pluginFile("bin/coinbase"), "watchlist-refresh"]
    watchlistProc.running = true
  }

  function setPeriod(next) {
    if (!next || next === period) return
    if (snapshotProc.running) snapshotProc.running = false
    var nextSnapshot = Object.assign({}, root.snapshot)
    nextSnapshot.period = next
    root.snapshot = nextSnapshot
    root.chartHover = false
    root.chartHoverPrice = NaN
    root.chartHoverIndex = -1
    root.rowsRefreshPending = true
    refreshing = true
    root.applySnapshotOnExit = true
    snapshotProc.command = [pluginFile("bin/coinbase"), "snapshot", "--period", next, "--fast"]
    snapshotProc.running = true
    if (root.showingDetail && root.detailAsset)
      root.loadDetailChart(root.detailAsset, next)
  }

  function signIn() {
    if (root.signingIn) return
    signingIn = true
    loginStatus = ""
    Quickshell.execDetached([pluginFile("bin/coinbase"), "login"])
    root.dismiss()
  }

  function saveAndSignIn() {
    if (setupProc.running || !clientIdDraft || !clientSecretDraft) return
    signingIn = true
    loginStatus = "Saving OAuth app…"
    setupProc.command = [pluginFile("bin/coinbase"), "setup", "--stdin"]
    setupProc.running = true
  }

  function activateAuth() {
    if (root.signedIn) root.logout()
    else if (root.needsSetup && root.clientIdDraft && root.clientSecretDraft) root.saveAndSignIn()
    else if (!root.needsSetup) root.signIn()
  }

  function logout() {
    if (snapshotProc.running) snapshotProc.running = false
    if (rowProc.running) rowProc.running = false
    if (watchlistProc.running) watchlistProc.running = false
    root.signingIn = false
    root.loginStatus = ""
    var signedOut = Object.assign({}, root.snapshot)
    signedOut.authenticated = false
    signedOut.error = ""
    signedOut.user = ({})
    var publicRows = root.publicCachedRows(root.assets)
    var lead = root.leadPublicAsset(publicRows)
    signedOut.assets = publicRows
    signedOut.total = Number(lead && lead.price) || 0
    signedOut.mode = "market"
    signedOut.pnl = 0
    signedOut.pnlPercent = 0
    signedOut.sparkline = (lead && lead.rowSpark) || []
    signedOut.bar = ({
      pnl: 0,
      pnlPercent: 0,
      period: root.period,
      symbol: "BTC",
      productId: "BTC-USD",
      name: "Bitcoin",
      kind: "crypto",
      price: Number(lead && lead.price) || 0
    })
    root.snapshot = signedOut
    root.resetSignedOutView()
    logoutProc.running = true
  }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached([pluginFile("bin/coinbase"), "open", url])
    root.dismiss()
  }

  FileView {
    id: snapshotFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/coinbase/snapshot.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.receiveSnapshot(text())
  }

  FileView {
    id: loginStatusFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/coinbase/login-status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var data = {}
      try { data = JSON.parse(text() || "{}") } catch (e) { data = {} }
      var status = String(data.status || "")
      if (!Model.shouldHandleLoginStatus(status, root.signingIn, root.signedIn)) return
      if (status === "opening") {
        root.signingIn = true
        root.loginStatus = "Opening Coinbase…"
      } else if (status === "waiting") {
        root.signingIn = true
        root.loginStatus = "Waiting for Coinbase in your browser…"
        root.dismiss()
      } else if (status === "exchanging") {
        root.signingIn = true
        root.loginStatus = "Finishing sign-in…"
      } else if (status === "snapshot") {
        root.signingIn = true
        root.loginStatus = "Loading portfolio…"
        snapshotFile.reload()
      } else if (status === "done") {
        root.signingIn = false
        root.loginStatus = ""
        root.acceptSnapshotReload = true
        snapshotFile.reload()
      } else if (status === "error") {
        root.signingIn = false
        root.loginStatus = String(data.message || "Sign-in did not finish.")
      } else if (status === "logged-out") {
        root.signingIn = false
        root.loginStatus = ""
        root.resetSignedOutView()
        root.acceptSnapshotReload = true
        snapshotFile.reload()
      }
    }
  }

  FileView {
    id: detailCacheFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/coinbase/detail-cache.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = {}
      try { parsed = JSON.parse(text() || "{}") } catch (e) { parsed = {} }
      if (!parsed || typeof parsed !== "object") return
      root.detailCache = parsed
      if (!root.showingDetail || !root.detailLoading) return
      var cached = Model.cachedDetail(parsed, root.detailAsset, root.period)
      if (cached && cached.sparkline && cached.sparkline.length >= 2)
        root.detailChart = cached
    }
  }

  Process {
    id: snapshotProc
    command: [root.pluginFile("bin/coinbase"), "snapshot"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.refreshing = false
      root.acceptSnapshotReload = root.applySnapshotOnExit
      root.applySnapshotOnExit = false
      snapshotFile.reload()
      Qt.callLater(function() { root.refreshRows(root.rowsRefreshPending) })
      if (root.watchlistRefreshPending)
        Qt.callLater(function() { root.refreshWatchlist() })
    }
  }

  Process {
    id: rowProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      // Row charts are fetched lazily for the active tab. Unlike a general
      // background snapshot, this update must be visible while the panel is
      // open or the requested sparklines remain deferred until the next open.
      root.acceptSnapshotReload = true
      snapshotFile.reload()
      if (root.rowsRefreshPending)
        Qt.callLater(function() { root.refreshRows(true) })
    }
  }

  Process {
    id: setupProc
    stdinEnabled: true
    onStarted: {
      setupProc.write(JSON.stringify({
        client_id: root.clientIdDraft,
        client_secret: root.clientSecretDraft
      }) + "\n")
      root.clientSecretDraft = ""
    }
    onExited: function(code) {
      if (code === 0) root.signIn()
      else {
        root.signingIn = false
        root.loginStatus = "Could not save OAuth app."
      }
    }
  }

  Process {
    id: logoutProc
    command: [root.pluginFile("bin/coinbase"), "logout"]
    onExited: {
      root.signingIn = false
      root.loginStatus = ""
      root.acceptSnapshotReload = true
      snapshotFile.reload()
    }
  }

  Process {
    id: watchlistProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      snapshotFile.reload()
      if (root.watchlistRefreshPending)
        Qt.callLater(function() { root.refreshWatchlist() })
      else if (root.marketTab === "watchlist")
        Qt.callLater(function() { root.refreshRows(false) })
    }
  }

  Process {
    id: chartProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.showingDetail || root.chartProcSeq !== root.chartSeq) return
        var raw = String(text || "")
        if (raw.indexOf("{") === -1) return
        try {
          var data = JSON.parse(raw)
          var got = String(data.productId || data.id || "").toUpperCase()
          var want = String(root.chartWantId || root.tickerId(root.detailAsset) || "").toUpperCase()
          if (want && got && got !== want && got.split("-")[0] !== want.split("-")[0]) return
          root.detailChart = data
        } catch (e) {
          root.detailChart = ({})
        }
        root.detailLoading = false
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.chartProcSeq === root.chartSeq) root.detailLoading = false
    }
  }

  Process {
    id: tickerProc
    onExited: function(code) {
      root.refreshing = false
      root.acceptSnapshotReload = true
      snapshotFile.reload()
      if (code === 0) {
        root.searchQuery = ""
        root.searchResults = []
        root.listCursor = 0
        if (searchField) searchField.text = ""
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.showingDetail || !root.searching) return
        var rows = Model.parseSearch(text)
        var seen = {}
        var vis = root.visibleAssets || []
        for (var i = 0; i < vis.length; i++)
          seen[String(vis[i].id || "").toUpperCase()] = true
        var out = []
        for (var j = 0; j < rows.length; j++) {
          var id = String(rows[j].id || "").toUpperCase()
          if (seen[id]) continue
          out.push(rows[j])
        }
        root.searchResults = out
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 280
    onTriggered: {
      if (root.showingDetail) return
      var q = String(root.searchQuery || "").replace(/^\s+|\s+$/g, "")
      if (q.length < 2) {
        root.searchResults = []
        return
      }
      searchProc.command = [root.pluginFile("bin/coinbase"), "search", q]
      searchProc.running = true
    }
  }

  Timer {
    id: rowScrollDebounce
    interval: 180
    onTriggered: root.refreshRows(false)
  }

  Timer {
    interval: 60000
    running: root.opened && root.signedIn
    repeat: true
    onTriggered: root.refreshWatchlist()
  }

  component AuthButton: Rectangle {
    id: authBtn
    property string label: "Sign in"
    property bool primary: true
    property bool enabled: true
    property bool compact: false

    implicitWidth: Math.max(compact ? Style.space(56) : Style.space(88), authLabel.implicitWidth + Style.space(compact ? 14 : 24))
    implicitHeight: compact ? Style.space(24) : Style.space(32)
    radius: Style.cornerRadius
    color: authMouse.pressed
      ? Style.pressedFillFor(root.foreground, Color.accent)
      : (authMouse.containsMouse
        ? Style.hoverFillFor(root.foreground, Color.accent)
        : (primary ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"))
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: primary ? root.foreground : root.muted
    opacity: enabled ? 1 : 0.55

    Text {
      id: authLabel
      anchors.centerIn: parent
      text: authBtn.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: compact ? Style.font.bodySmall : Style.font.body
      font.bold: primary
    }

    MouseArea {
      id: authMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: authBtn.enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: authBtn.clicked()
    }

    signal clicked()
  }

  component AssetRow: Rectangle {
    id: assetRow
    required property var modelData
    required property int index
    width: parent ? parent.width : 0
    height: Style.space(48)
    radius: Style.cornerRadius
    color: (index === root.listCursor)
      ? Style.hoverFillFor(root.foreground, Color.accent)
      : "transparent"

    Column {
      id: assetCol
      z: 1
      width: parent.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - Style.space(220)
          spacing: Style.space(1)
          Row {
            spacing: Style.space(6)
            Text {
              text: String(modelData.name || modelData.id)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: !root.signedIn && root.isBarAsset(modelData)
              elide: Text.ElideRight
            }
            Text {
              visible: !root.signedIn && root.isBarAsset(modelData)
              text: "󰐃"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Text {
            text: [modelData.id, root.marketTypeLabel(modelData)].filter(function(s) { return !!s }).join(" · ")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Sparkline {
          width: Style.space(72)
          height: Style.space(28)
          compact: true
          interactive: false
          values: modelData.rowSpark || []
          stroke: root.rowPeriodColor(modelData)
          fill: Util.alpha(root.rowPeriodColor(modelData), 0.18)
          foreground: root.foreground
          muted: root.muted
          fontFamily: root.fontFamily
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: Style.space(80)
          Text {
            anchors.right: parent.right
            text: Number(modelData.price) > 0 ? Model.formatUsd(modelData.price, Number(modelData.price) >= 100 ? 2 : 4) : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: parent.right
            text: isFinite(root.rowPeriodPercent(modelData)) ? Model.formatPercent(root.rowPeriodPercent(modelData)) : "—"
            color: root.rowPeriodColor(modelData)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      z: 2
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (root.hoverSelectEnabled) root.listCursor = index
      }
      onPositionChanged: {
        root.hoverSelectEnabled = true
        root.listCursor = index
      }
      onClicked: root.chooseAsset(modelData)
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "coinbase"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible && keyCatcher) keyCatcher.forceActiveFocus()

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.55)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "/"
        context: Qt.WindowShortcut
        onActivated: root.focusSearch()
      }
      Shortcut {
        enabled: root.opened && root.showingDetail && !root.signedIn && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "P"
        context: Qt.WindowShortcut
        onActivated: root.pinToBar(root.detailAsset)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Down"
        context: Qt.WindowShortcut
        onActivated: root.moveListCursor(1)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Up"
        context: Qt.WindowShortcut
        onActivated: root.moveListCursor(-1)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Return"
        context: Qt.WindowShortcut
        onActivated: root.activateCursor()
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Enter"
        context: Qt.WindowShortcut
        onActivated: root.activateCursor()
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !root.searching && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Left"
        context: Qt.WindowShortcut
        onActivated: root.moveTab(-1)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !root.searching && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Right"
        context: Qt.WindowShortcut
        onActivated: root.moveTab(1)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "Home"
        context: Qt.WindowShortcut
        onActivated: root.moveListEdge(false)
      }
      Shortcut {
        enabled: root.opened && !root.showingDetail && !searchField.activeFocus && !clientIdField.activeFocus && !clientSecretField.activeFocus
        sequence: "End"
        context: Qt.WindowShortcut
        onActivated: root.moveListEdge(true)
      }

      Keys.onEscapePressed: function(event) {
        if (root.showingDetail) {
          root.closeDetail()
          event.accepted = true
        } else root.dismiss()
      }
      Keys.onPressed: function(event) {
        var typing = searchField.activeFocus || clientIdField.activeFocus || clientSecretField.activeFocus
        if (event.key === Qt.Key_Escape) {
          if (root.showingDetail) {
            root.closeDetail()
            event.accepted = true
            return
          }
        }
        if ((event.key === Qt.Key_Slash || event.text === "/") && !typing && !root.showingDetail) {
          root.focusSearch()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_R && !typing) {
          root.refresh(true)
          event.accepted = true
          return
        }
        if (!typing && !root.showingDetail && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
          root.moveListCursor(event.key === Qt.Key_J ? 1 : -1)
          event.accepted = true
          return
        }
        if (!typing && !root.showingDetail && !root.searching && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
          root.moveTab(event.key === Qt.Key_L ? 1 : -1)
          event.accepted = true
        }
      }

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(Style.space(480), parent.width - Style.space(40))
        height: Math.min(Style.space(600), parent.height - Style.space(36))
        color: Color.popups.background
        radius: Style.cornerRadius
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

        MouseArea {
          anchors.fill: parent
          z: 0
          onClicked: function(m) { m.accepted = true }
        }

        Item {
          id: chrome
          z: 1
          anchors.fill: parent
          anchors.topMargin: card.borderTop + root.pad
          anchors.bottomMargin: card.borderBottom + root.pad
          anchors.leftMargin: card.borderLeft + root.pad
          anchors.rightMargin: card.borderRight + root.pad

          Column {
            id: topChrome
            anchors.top: parent.top
            width: parent.width
            spacing: Style.space(10)

          Item {
            width: parent.width
            height: Math.max(Style.space(32), detailActions.implicitHeight, headerAuth.implicitHeight, accountActions.implicitHeight)

            Row {
              id: titleRow
              anchors.left: parent.left
              anchors.right: detailActions.visible ? detailActions.left : (accountActions.visible ? accountActions.left : headerAuth.left)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              CoinbaseIcon {
                id: headerIcon
                visible: !root.showingDetail
                iconSize: Style.font.title
                color: root.foreground
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: backLabel
                visible: root.showingDetail
                text: "‹"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(8)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.closeDetail()
                }
              }

              Text {
                id: headerCopy
                width: Math.max(0, titleRow.width - (headerIcon.visible ? headerIcon.width + titleRow.spacing : 0) - (backLabel.visible ? backLabel.width + titleRow.spacing : 0))
                text: root.showingDetail
                  ? String((detailAsset && (detailAsset.name || detailAsset.id)) || "Asset")
                  : (root.signedIn && snapshot.user && snapshot.user.name ? snapshot.user.name : "Coinbase")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              id: detailActions
              visible: root.showingDetail
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Button {
                visible: !root.signedIn
                text: root.isBarAsset(root.detailAsset) ? "Pinned" : "Pin"
                bordered: true
                selected: root.isBarAsset(root.detailAsset)
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: root.pinToBar(root.detailAsset)
              }
              Button {
                text: "Buy"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: root.openUrl((root.detailAsset && (root.detailAsset.buyUrl || root.detailAsset.url)) || "")
              }
              Button {
                text: "Sell"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: root.openUrl((root.detailAsset && (root.detailAsset.sellUrl || root.detailAsset.url)) || "")
              }
            }

            Row {
              id: accountActions
              visible: root.signedIn && !root.showingDetail
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              AuthButton {
                compact: true
                label: "My account"
                primary: false
                onClicked: root.openUrl("https://www.coinbase.com/")
              }
              AuthButton {
                compact: true
                label: "Sign out"
                primary: false
                onClicked: root.logout()
              }
            }

            AuthButton {
              id: headerAuth
              visible: !root.signedIn && !root.needsSetup && !root.showingDetail
              width: visible ? implicitWidth : 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              compact: true
              label: root.signingIn ? "Signing in…" : "Sign in"
              primary: true
              enabled: !root.signingIn
              onClicked: root.signIn()
            }
          }

          Column {
            visible: !root.signedIn && root.needsSetup
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "This copy has no OAuth broker yet. Deploy broker/ or paste a Coinbase OAuth client ID and secret."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: clientIdField
              width: parent.width
              placeholderText: "OAuth client ID"
              foreground: root.foreground
              font.family: root.fontFamily
              text: root.clientIdDraft
              onTextChanged: root.clientIdDraft = text
              Keys.onEscapePressed: root.dismiss()
            }

            TextField {
              id: clientSecretField
              width: parent.width
              placeholderText: "OAuth client secret (stored locally, never in git)"
              password: true
              foreground: root.foreground
              font.family: root.fontFamily
              text: root.clientSecretDraft
              onTextChanged: root.clientSecretDraft = text
              Keys.onEscapePressed: root.dismiss()
            }

            AuthButton {
              width: parent.width
              height: Style.space(40)
              label: root.signingIn ? (root.loginStatus || "Signing in…") : "Save and sign in"
              primary: true
              enabled: !root.signingIn && root.clientIdDraft !== "" && root.clientSecretDraft !== ""
              onClicked: root.saveAndSignIn()
            }
          }

          Text {
            visible: !root.signedIn && !root.signingIn && root.loginStatus !== ""
            width: parent.width
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WordWrap
            text: root.loginStatus
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          }

          Column {
            id: chartColumn
            anchors.top: topChrome.bottom
            anchors.topMargin: Style.space(10)
            width: parent.width
            spacing: Style.space(6)

                Text {
                  visible: !root.showingDetail && !root.signedIn
                  width: parent.width
                  text: root.selectedAssetLabel
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }

                Column {
                  width: parent.width
                  spacing: Style.space(2)

                  Text {
                    text: root.authLoading && (!isFinite(root.displayPrice) || root.displayPrice <= 0)
                      ? "Loading portfolio…"
                      : Model.formatUsd(root.displayPrice, 2)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }

                  Row {
                    spacing: Style.space(8)
                    Text {
                      visible: !root.authLoading
                      text: Model.formatSignedUsd(root.displayPnl, 2)
                      color: Model.pnlColor(root.displayPnl, Color.accent, Color.urgent, root.foreground)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }
                    Text {
                      visible: !root.authLoading
                      text: Model.formatPercent(root.displayPnlPercent)
                      color: Model.pnlColor(root.displayPnlPercent, Color.accent, Color.urgent, root.foreground)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }
                    Text {
                      visible: root.chartHover && root.chartHoverTime !== ""
                      text: root.chartHoverTime
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      visible: (root.authLoading || root.refreshing || root.detailLoading) && !root.chartHover
                      text: root.authLoading ? "Loading details…" : "Updating…"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }

                Row {
                  spacing: Style.space(4)

                  Repeater {
                    model: root.periodOptions
                    Rectangle {
                      required property var modelData
                      readonly property bool current: modelData.value === root.period
                      radius: Style.space(6)
                      color: current ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                      implicitWidth: pillLabel.implicitWidth + Style.space(14)
                      implicitHeight: pillLabel.implicitHeight + Style.space(8)

                      Text {
                        id: pillLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: current ? root.foreground : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: current
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setPeriod(modelData.value)
                      }
                    }
                  }
                }

                Sparkline {
                  width: parent.width
                  height: Style.space(120)
                  values: root.sparkline
                  stroke: root.pnlColor
                  fill: Util.alpha(root.pnlColor, 0.16)
                  foreground: root.foreground
                  muted: root.muted
                  fontFamily: root.fontFamily
                  onHovered: function(active, price, index) {
                    root.chartHover = active
                    root.chartHoverPrice = price
                    root.chartHoverIndex = index
                  }
                }

                Item {
                  visible: !root.showingDetail
                  width: parent.width
                  height: searchField.implicitHeight

                  TextField {
                    id: searchField
                    width: parent.width
                    enabled: !root.showingDetail
                    placeholderText: "Search"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    rightPadding: Style.space(88)
                    text: root.searchQuery
                    onTextChanged: {
                      if (root.showingDetail) {
                        if (text !== "") text = ""
                        root.searchQuery = ""
                        return
                      }
                      root.searchQuery = text
                      root.resetHoverSelect()
                      searchDebounce.restart()
                    }
                    Keys.onEscapePressed: function(event) {
                      text = ""
                      root.searchQuery = ""
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                    Keys.onDownPressed: root.moveListCursor(1)
                    Keys.onUpPressed: root.moveListCursor(-1)
                    Keys.onReturnPressed: root.activateCursor()
                    Keys.onEnterPressed: root.activateCursor()
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: String(searchField.text) === "" && !searchField.activeFocus
                    spacing: Style.space(6)

                    Text {
                      text: "press"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                      width: slashHint.implicitWidth + Style.space(10)
                      height: slashHint.implicitHeight + Style.space(4)
                      radius: 4
                      color: "transparent"
                      border.width: 1
                      border.color: root.muted
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: slashHint
                        anchors.centerIn: parent
                        text: "/"
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }
          }

          Item {
            id: body
            anchors.top: chartColumn.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true

            Column {
              id: marketHeader
              visible: !root.searching && !root.showingDetail
              anchors.top: parent.top
              width: parent.width
              spacing: Style.space(8)

              Flickable {
                width: parent.width
                height: marketTabRow.implicitHeight
                contentWidth: marketTabRow.implicitWidth
                contentHeight: height
                clip: true
                interactive: contentWidth > width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                  id: marketTabRow
                  spacing: Style.space(4)
                  Repeater {
                    model: root.marketTabs
                    Button {
                      required property var modelData
                      text: modelData.label
                      selected: modelData.value === root.marketTab
                      bordered: true
                      foreground: root.foreground
                      accent: Color.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      focusable: false
                      onClicked: {
                        root.marketTabUserSelected = true
                        root.tabSynced = true
                        root.marketTab = modelData.value
                        root.resetHoverSelect()
                        if (flick) flick.contentY = 0
                        Qt.callLater(function() { root.refreshRows(false) })
                      }
                    }
                  }
                }
              }

            }

            Flickable {
              id: detailFlick
              anchors.fill: parent
              visible: root.showingDetail && !root.searching
              contentWidth: width
              contentHeight: detailBlock.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              flickableDirection: Flickable.VerticalFlick

              Column {
                id: detailBlock
                width: detailFlick.width
                spacing: Style.space(14)

                Row {
                  width: parent.width
                  spacing: Style.space(16)
                  visible: Number(detailChart.open) > 0 || Number(detailChart.high) > 0 || Number(detailChart.low) > 0 || Number(detailChart.volume) > 0

                  Repeater {
                    model: [
                      { label: "OPEN", value: Number(detailChart.open) > 0 ? Model.formatUsd(detailChart.open, Number(detailChart.open) >= 100 ? 2 : 4) : "—" },
                      { label: "HIGH", value: Number(detailChart.high) > 0 ? Model.formatUsd(detailChart.high, Number(detailChart.high) >= 100 ? 2 : 4) : "—" },
                      { label: "LOW", value: Number(detailChart.low) > 0 ? Model.formatUsd(detailChart.low, Number(detailChart.low) >= 100 ? 2 : 4) : "—" },
                      {
                        label: "24H VOL",
                        value: Number(detailChart.volume) > 0
                          ? (["stock", "commodity"].indexOf(String(detailChart.kind || "")) !== -1
                              ? Model.formatCompactNumber(detailChart.volume)
                              : Model.formatCompactUsd(detailChart.volume))
                          : "—"
                      }
                    ]
                    Column {
                      required property var modelData
                      width: (detailBlock.width - Style.space(48)) / 4
                      spacing: Style.space(4)
                      Text {
                        text: modelData.label
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                      }
                      Text {
                        text: modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                      }
                    }
                  }
                }

                Grid {
                  width: parent.width
                  columns: 3
                  columnSpacing: Style.space(16)
                  rowSpacing: Style.space(12)
                  visible: Array.isArray(detailChart.stats) && detailChart.stats.length > 0

                  Repeater {
                    model: detailChart.stats || []
                    Column {
                      required property var modelData
                      width: (detailBlock.width - Style.space(32)) / 3
                      spacing: Style.space(4)
                      Text {
                        text: String(modelData.label || "")
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                      }
                      Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: String(modelData.value || "—")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                      }
                    }
                  }
                }

                Text {
                  visible: (!Array.isArray(detailChart.stats) || detailChart.stats.length === 0) && !root.detailLoading
                  text: "No extra market stats for this asset yet."
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Flickable {
              id: flick
              anchors.top: marketHeader.bottom
              anchors.topMargin: Style.space(8)
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              visible: !root.searching && !root.showingDetail
              contentWidth: width
              contentHeight: marketsBlock.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              flickableDirection: Flickable.VerticalFlick
              onContentYChanged: {
                if (root.opened && moving) rowScrollDebounce.restart()
              }

              HoverHandler {
                id: listHover
                onPointChanged: root.notePointerMove(listHover)
              }

                Column {
                  id: marketsBlock
                  width: flick.width
                  spacing: Style.space(8)

                  Text {
                    visible: root.snapshotReady && !root.authLoading && root.visibleAssets.length === 0
                    text: root.marketTab === "watchlist" ? "Nothing on your Coinbase watchlist." : "Nothing in this tab yet."
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: (!root.snapshotReady || root.authLoading) && root.visibleAssets.length === 0
                    text: root.authLoading ? "Loading your Coinbase portfolio…" : "Updating…"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Repeater {
                    id: marketAssetRepeater
                    model: root.visibleAssets
                    AssetRow {}
                  }

                  Text {
                    visible: String(snapshot.error || "") !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: String(snapshot.error || "")
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
            }

            Rectangle {
              id: searchOverlay
              visible: root.searching && !root.showingDetail
              anchors.fill: parent
              z: 30
              color: Util.alpha(Color.popups.background, 0.88)
              radius: Style.cornerRadius
              clip: true
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.08)

              HoverHandler {
                id: overlayHover
                onPointChanged: root.notePointerMove(overlayHover)
              }

              Flickable {
                id: overlayFlick
                anchors.fill: parent
                anchors.margins: Style.space(4)
                contentWidth: width
                contentHeight: overlayCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                flickableDirection: Flickable.VerticalFlick

                Column {
                  id: overlayCol
                  width: overlayFlick.width
                  spacing: Style.space(2)

                  Text {
                    visible: root.visibleAssets.length === 0
                    width: parent.width
                    text: "No matching assets"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Repeater {
                    id: searchAssetRepeater
                    model: root.visibleAssets
                    AssetRow {}
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
