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
  property bool periodChangeRequested: false
  property bool detailPeriodChangeRequested: false
  readonly property bool showUpdating: opened && Model.shouldShowUpdating({
    hasData: snapshotReady && (assets.length > 0 || showingDetail),
    hasChart: sparkline.length >= 2,
    snapshotRunning: snapshotProc.running,
    chartRunning: chartProc.running,
    periodChange: periodChangeRequested,
    detailPeriodChange: detailPeriodChangeRequested,
    detailMissing: showingDetail && (!Array.isArray(detailChart.stats) || detailChart.stats.length === 0)
  })
  property double statusNow: Date.now()
  property bool signingIn: false
  property string loginStatus: ""
  property string loginPhase: ""
  property double loginRequestedAt: 0
  property bool dismissAfterLoginLaunch: false
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
  property var detailWatchlistState: ({})
  property string watchlistMessage: ""
  property var watchlistPayload: null
  property string watchlistAction: "state"
  property string watchlistActionKey: ""
  property bool watchlistResponseReceived: false
  property var watchlistBeforeAction: null
  property var watchlistOrderOverride: null
  property string watchlistReorderMessage: ""
  property var watchlistDragRows: null
  property int watchlistDragIndex: -1
  property int watchlistDropIndex: -1
  property real watchlistDragY: 0
  property real watchlistPressY: 0
  property bool watchlistDragging: false
  onCanReorderWatchlistChanged: if (!canReorderWatchlist) cancelWatchlistDrag()
  readonly property bool watchlistReorderView: opened && signedIn && !showingDetail && !searching && marketTab === "watchlist"
  readonly property bool canReorderWatchlist: watchlistReorderView && watchlistStatus.ready === true
    && watchlistStatus.canUpdate === true && !watchlistStatus.error
    && !watchlistActionProc.running && !watchlistProc.running && !watchlistRefreshPending
    && watchlistOrderOverride === null
  property var detailChart: ({})
  property var detailCache: ({})
  property bool detailLoading: false
  property var lastPortfolio: ({})
  property int chartSeq: 0
  property int chartProcSeq: 0
  property string chartWantId: ""
  property bool rowsRefreshPending: false
  property bool watchlistRefreshPending: false
  property var pendingTickerPayload: null

  readonly property bool signedIn: snapshot.authenticated === true
  readonly property bool authLoading: root.signedIn && snapshot.loading === true
  readonly property var watchlistStatus: snapshot.watchlistStatus || ({})
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
        { value: "index", label: "Indices" }
      ]
    : [
        { value: "all", label: "All" },
        { value: "crypto", label: "Crypto" },
        { value: "stock", label: "Stocks" },
        { value: "commodity", label: "Commodities" },
        { value: "index", label: "Indices" }
      ]
  readonly property bool showingDetail: detailAsset !== null
  readonly property bool detailIsCrypto: root.showingDetail && Model.marketCategory(root.detailAsset || {}) === "crypto"
  readonly property string period: String(snapshot.period || "day")
  readonly property var assets: snapshot.assets || []
  readonly property bool searching: String(searchQuery).replace(/^\s+|\s+$/g, "").length > 0
  readonly property var visibleAssets: watchlistDragRows || filteredAssets(searchQuery, assets)
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
  onChartHoverChanged: {
    if (!chartHover && pendingSnapshotRaw !== "") {
      var pending = pendingSnapshotRaw
      pendingSnapshotRaw = ""
      root.applySnapshot(pending)
    }
  }
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

  function formatDetailPrice(value) {
    var price = Number(value)
    return price > 0 ? Model.formatUsd(price, price >= 100 ? 2 : 4) : "—"
  }

  function detailRangeText() {
    var low = Number(detailChart.low)
    var high = Number(detailChart.high)
    if (!(low > 0) || !(high > 0)) return "—"
    return root.formatDetailPrice(low) + " – " + root.formatDetailPrice(high)
  }

  function receiveSnapshot(raw) {
    var serialized = String(raw || "")
    if (serialized !== "" && serialized === root.lastSnapshotRaw && root.watchlistOrderOverride === null) {
      root.acceptSnapshotReload = false
      return true
    }
    var next = Model.parseSnapshot(serialized, null)
    if (!next) return false
    var recovering = Model.snapshotNeedsRefresh(root.snapshot, Date.now())
    if (root.opened && root.chartHover && root.snapshotReady && !root.acceptSnapshotReload && !recovering) {
      root.pendingSnapshotRaw = serialized
      return true
    }
    root.acceptSnapshotReload = false
    root.pendingSnapshotRaw = ""
    // Don't keep a stale snapshot (or its hovered price) on screen after
    // recovery just because the pointer was left over the chart.
    if (recovering) root.chartHover = false
    return root.applySnapshot(serialized, next)
  }

  function applySnapshot(raw, parsed) {
    var serialized = String(raw || "")
    var next = parsed || Model.parseSnapshot(serialized, null)
    if (!next) return false
    root.lastSnapshotRaw = serialized
    var wasSigned = root.signedIn
    var selectedKey = Model.assetKey(root.visibleAssets[root.listCursor])
    var previousCursor = root.listCursor
    snapshot = next
    if (root.watchlistOrderOverride !== null && !watchlistActionProc.running
        && next.watchlistStatus && next.watchlistStatus.ready && !next.watchlistStatus.error) {
      root.watchlistOrderOverride = null
      root.watchlistReorderMessage = ""
    }
    root.statusNow = Date.now()
    root.listCursor = Model.selectionIndex(root.visibleAssets, selectedKey, previousCursor)
    root.hoverSelectEnabled = false
    root.snapshotReady = true
    root.capturePortfolio(snapshot)
    if (root.showingDetail && root.signedIn && !watchlistActionProc.running)
      Qt.callLater(root.prepareWatchlistAction)
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
    root.watchlistOrderOverride = null
    root.watchlistReorderMessage = ""
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
    if (handler && handler.hovered && handler.point)
      root.notePointerPosition(handler.point.scenePosition)
  }

  function notePointerPosition(pos) {
    if (!pos) return
    // Row-local coordinates change when the list scrolls beneath a stationary
    // pointer. Only movement in the window may take selection from the keys.
    var moved = Model.pointerMoved(root.pointerX, root.pointerY, pos.x, pos.y)
    if (moved)
      root.hoverSelectEnabled = true
    if (root.pointerX < 0 || moved) {
      root.pointerX = pos.x
      root.pointerY = pos.y
    }
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
    if (snapshotProc.running || rowProc.running || tickerProc.running) {
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
      if (!Model.isVisibleAsset(a)) continue
      var aid = String(a.id || "")
      var aname = String(a.name || "")
      if (!aid.replace(/^\s+|\s+$/g, "") && !aname.replace(/^\s+|\s+$/g, "")) continue
      var junk = aid.indexOf("v1:equity") === 0 || (aid.length >= 16 && /^[01]+$/.test(aid))
      if (junk && (aname === aid || aname === "Stock")) continue
      if (a.watchlistUnavailable) continue
      if (!searching) {
        if (tab === "watchlist") {
          if (root.watchlistStatus.source !== "simple" || !a.watchlist) continue
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
        if (!Model.isVisibleAsset(hit)) continue
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
        var ao = Model.watchlistRowOrder(a, root.watchlistOrderOverride)
        var bo = Model.watchlistRowOrder(b, root.watchlistOrderOverride)
        if (!isFinite(ao)) ao = 1e9
        if (!isFinite(bo)) bo = 1e9
        if (ao !== bo) return ao - bo
        return String(a.id || "").localeCompare(String(b.id || ""))
      })
    } else out.sort(Model.compareMarketVolume)
    return out
  }

  function open(payloadJson) {
    root.periodChangeRequested = false
    root.detailPeriodChangeRequested = false
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
    // Opening the panel requests current data, even when the bar's cached
    // snapshot is recent. A running refresh is shared instead of duplicated.
    refresh(true)
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
    root.hoverSelectEnabled = false
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
    root.hoverSelectEnabled = false
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
      view.cancelFlick()
      var mapped = item.mapToItem(view.contentItem, 0, 0)
      view.contentY = Model.cursorScrollY(view.contentY, view.height, view.contentHeight, mapped.y, item.height)
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

  function setBarTicker(row) {
    var productId = root.tickerId(row)
    if (!row || !productId || root.signedIn) return
    // A user-selected pin takes priority over any older background writer.
    if (snapshotProc.running) snapshotProc.running = false
    if (rowProc.running) rowProc.running = false
    if (tickerProc.running) tickerProc.running = false
    var cmd = [pluginFile("bin/coinbase"), "ticker", productId]
    if (row.id) cmd.push("--symbol", String(row.id))
    cmd.push("--stdin")
    root.pendingTickerPayload = {
      asset: {
        id: String(row.id || ""),
        name: String(row.name || row.id || ""),
        productId: productId,
        kind: String(row.kind || "crypto"),
        marketCategory: String(row.marketCategory || ""),
        price: Number(row.price) || 0,
        pnlPercent: Number(row.pnlPercent) || 0,
        dayPnlPercent: Number(row.dayPnlPercent) || 0,
        rowSpark: row.rowSpark || [],
        rowSparkPeriod: String(row.rowSparkPeriod || root.period),
        rowSparkVersion: Number(row.rowSparkVersion) || 0,
        volume24h: Number(row.volume24h) || 0,
        yahoo: String(row.yahoo || ""),
        url: String(row.url || "")
      }
    }
    tickerProc.command = cmd
    tickerProc.running = true
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
    root.setBarTicker(row)
  }

  function chooseAsset(row) {
    if (!row) return
    root.openDetail(row)
  }

  function openDetail(row) {
    if (!Model.isVisibleAsset(row)) return
    root.detailAsset = row
    root.detailWatchlistState = ({})
    root.watchlistMessage = ""
    searchDebounce.stop()
    if (searchProc.running) searchProc.running = false
    root.searchQuery = ""
    root.searchResults = []
    if (searchField) searchField.text = ""
    root.loadDetailChart(row)
    root.prepareWatchlistAction()
    Qt.callLater(function() {
      if (root.showingDetail && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function loadDetailChart(row, periodOverride, userPeriodChange) {
    if (!row) return
    root.chartSeq += 1
    root.chartProcSeq = root.chartSeq
    root.chartWantId = String(root.tickerId(row) || "").toUpperCase()
    if (chartProc.running) chartProc.running = false
    root.detailPeriodChangeRequested = userPeriodChange === true
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
    root.detailWatchlistState = ({})
    root.watchlistMessage = ""
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
    root.dismissAfterLoginLaunch = false
    root.periodChangeRequested = false
    root.detailPeriodChangeRequested = false
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
    root.applySnapshotOnExit = force === true
    root.periodChangeRequested = false
    snapshotProc.command = [pluginFile("bin/coinbase"), "snapshot", "--period", period]
    if (!force) snapshotProc.command.push("--max-age", "10")
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

  function prepareWatchlistAction() {
    if (!root.signedIn || !root.showingDetail || watchlistActionProc.running) return
    root.startWatchlistAction("state", root.detailAsset)
  }

  function cancelWatchlistDrag() {
    root.watchlistDragging = false
    root.watchlistDragIndex = -1
    root.watchlistDropIndex = -1
    root.watchlistDragRows = null
  }

  function updateWatchlistDrag(y) {
    if (root.watchlistDragIndex < 0) return
    root.watchlistDragY = y
    if (Math.abs(y - root.watchlistPressY) >= Qt.styleHints.startDragDistance)
      root.watchlistDragging = true
    var row = marketAssetRepeater.itemAt(0)
    if (!row) return
    var slot = Math.floor((y + flick.contentY - row.y + marketsBlock.spacing / 2)
      / (row.height + marketsBlock.spacing))
    root.watchlistDropIndex = Math.max(0, Math.min(root.visibleAssets.length - 1, slot))
  }

  function finishWatchlistDrag(inside) {
    var from = root.watchlistDragIndex
    var to = root.watchlistDropIndex
    var rows = root.watchlistDragRows
    var body = inside && root.watchlistDragging ? Model.watchlistMoveRequest(rows || [], from, to - from) : null
    // Defer model changes until the handle has finished processing release.
    Qt.callLater(function() {
      if (root.watchlistDragRows !== rows || root.watchlistDragIndex !== from) return
      root.cancelWatchlistDrag()
      if (body) root.moveWatchlistItem(from, to - from, body)
    })
  }

  Timer {
    interval: 16
    repeat: true
    running: root.watchlistDragging
    onTriggered: {
      var edge = Style.space(32)
      var direction = root.watchlistDragY < edge ? -1 : (root.watchlistDragY > flick.height - edge ? 1 : 0)
      if (!direction) return
      flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + direction * Style.space(8)))
      root.updateWatchlistDrag(root.watchlistDragY)
    }
  }

  function moveWatchlistItem(index, delta, request) {
    if (!root.canReorderWatchlist) return
    var body = request || Model.watchlistMoveRequest(root.visibleAssets, index, delta)
    var reordered = Model.reorderedWatchlist(root.watchlistStatus.items, body)
    if (!body || !reordered) return
    var selected = ""
    for (var i = 0; i < root.visibleAssets.length; i++)
      if (Model.watchlistItemKey(root.visibleAssets[i].watchlistItem) === Model.watchlistItemKey(body.item))
        selected = Model.assetKey(root.visibleAssets[i])
    root.watchlistAction = "reorder"
    root.watchlistPayload = body
    root.watchlistResponseReceived = false
    root.watchlistReorderMessage = ""
    root.hoverSelectEnabled = false
    root.watchlistOrderOverride = reordered
    root.listCursor = Model.selectionIndex(root.visibleAssets, selected, index)
    root.ensureCursorVisible()
    watchlistActionProc.command = [root.pluginFile("bin/coinbase"), "watchlist-action", "reorder"]
    watchlistActionProc.running = true
  }

  function finishWatchlistReorder(result) {
    if (!root.signedIn) return
    var selected = Model.assetKey(root.visibleAssets[root.listCursor])
    if (result.ok && Array.isArray(result.items)) {
      root.snapshot = Model.withWatchlistOrder(root.snapshot, result.items)
      root.watchlistOrderOverride = null
    } else if (!result.ok) {
      // Roll back only the temporary order, not newer prices or membership.
      root.watchlistOrderOverride = null
    }
    root.watchlistReorderMessage = result.message || (result.ok ? "" : "Could not confirm the new order. Refreshing before another attempt.")
    if (root.watchlistReorderView) {
      root.listCursor = Model.selectionIndex(root.visibleAssets, selected, root.listCursor)
      root.ensureCursorVisible()
    }
  }

  function startWatchlistAction(action, payload) {
    if (watchlistActionProc.running || !root.signedIn || !root.showingDetail) return
    root.watchlistAction = action
    root.watchlistActionKey = Model.assetKey(root.detailAsset)
    root.watchlistPayload = payload
    root.watchlistResponseReceived = false
    if (action !== "state") {
      root.watchlistBeforeAction = root.detailWatchlistState
      root.detailWatchlistState = Model.optimisticWatchlistState(root.detailWatchlistState, action)
      root.watchlistMessage = ""
    }
    watchlistActionProc.command = [root.pluginFile("bin/coinbase"), "watchlist-action", action]
    watchlistActionProc.running = true
  }

  function toggleWatchlist() {
    // Ignore repeated clicks without disabling/repainting the button while a
    // request is running. The star changes immediately and rolls back on error.
    if (watchlistActionProc.running) return
    if (!root.detailWatchlistState.ready) {
      root.refreshWatchlist()
      root.prepareWatchlistAction()
      return
    }
    if (!root.detailWatchlistState.canUpdate) return
    root.startWatchlistAction(root.detailWatchlistState.watched ? "remove" : "add", {item: root.detailWatchlistState.item})
  }

  function setPeriod(next) {
    if (!next || next === period) return
    if (snapshotProc.running) snapshotProc.running = false
    root.periodChangeRequested = true
    var nextSnapshot = Object.assign({}, root.snapshot)
    nextSnapshot.period = next
    root.snapshot = nextSnapshot
    root.chartHover = false
    root.chartHoverPrice = NaN
    root.chartHoverIndex = -1
    root.rowsRefreshPending = true
    root.applySnapshotOnExit = true
    snapshotProc.command = [pluginFile("bin/coinbase"), "snapshot", "--period", next, "--fast"]
    snapshotProc.running = true
    if (root.showingDetail && root.detailAsset)
      root.loadDetailChart(root.detailAsset, next, true)
  }

  function signIn() {
    if (root.signingIn && root.loginPhase !== "waiting") return
    signingIn = true
    loginPhase = "opening"
    loginRequestedAt = Date.now()
    dismissAfterLoginLaunch = true
    loginStatus = "Opening Coinbase…"
    Quickshell.execDetached([pluginFile("bin/coinbase"), "login"])
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
    signedOut.watchlistStatus = ({})
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

  function applyLoginStatus(data) {
    // Give the detached helper time to acquire its lock and publish status.
    if (!data.active && Date.now() - root.loginRequestedAt < 1500) return
    var status = String(data.status || "")
    if (!Model.shouldHandleLoginStatus(status, root.signingIn, root.signedIn, data.active)) return
    root.loginPhase = status
    if (status === "opening") {
      root.signingIn = true
      root.loginStatus = "Opening Coinbase…"
    } else if (status === "waiting") {
      root.signingIn = true
      root.loginStatus = String(data.message || "Approve access in Coinbase. If offered a portfolio choice, select All portfolios and wallets.")
      if (root.dismissAfterLoginLaunch && !data.message) {
        root.dismissAfterLoginLaunch = false
        root.dismiss()
      }
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

  Process {
    id: loginStateProc
    command: [root.pluginFile("bin/coinbase"), "login-status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.applyLoginStatus(JSON.parse(text || "{}")) } catch (e) {}
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Timer {
    interval: 1000
    running: root.opened && (!root.signedIn || root.signingIn)
    repeat: true
    triggeredOnStart: true
    onTriggered: { if (!loginStateProc.running) loginStateProc.running = true }
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

  RefreshProcess {
    id: snapshotProc
    onRunningChanged: {
      if (!running) root.periodChangeRequested = false
    }
    command: [root.pluginFile("bin/coinbase"), "snapshot"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.acceptSnapshotReload = root.applySnapshotOnExit
      root.applySnapshotOnExit = false
      snapshotFile.reload()
      Qt.callLater(function() { root.refreshRows(root.rowsRefreshPending) })
      if (root.watchlistRefreshPending)
        Qt.callLater(function() { root.refreshWatchlist() })
    }
  }

  RefreshProcess {
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
      if (code === 0) {
        root.signingIn = false
        root.signIn()
      }
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

  RefreshProcess {
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

  RefreshProcess {
    id: watchlistActionProc
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(root.watchlistPayload || {}) + "\n")
      root.watchlistPayload = null
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result
        try { result = JSON.parse(String(text || "")) } catch (e) { return }
        root.watchlistResponseReceived = true
        if (root.watchlistAction === "reorder") {
          root.finishWatchlistReorder(result)
          return
        }
        if (root.watchlistAction !== "state") snapshotFile.reload()
        if (!root.showingDetail || root.watchlistActionKey !== Model.assetKey(root.detailAsset)) return
        if (root.watchlistAction === "state") {
          root.detailWatchlistState = Model.reconcileWatchlistState(root.detailWatchlistState, result)
          if (!result.ok || result.message) root.watchlistMessage = result.message || "Watchlist state unavailable."
          else if (!result.canUpdate) root.watchlistMessage = "Sign out and back in to grant watchlist editing access."
        } else {
          if (!result.ok && root.watchlistBeforeAction)
            root.detailWatchlistState = root.watchlistBeforeAction
          root.watchlistMessage = result.message || (result.ok ? "" : "Could not confirm the watchlist update.")
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.watchlistAction === "reorder") {
        if (!root.watchlistResponseReceived)
          root.finishWatchlistReorder({ok: false, message: "Request not confirmed. Refreshing the watchlist; the move will not be retried automatically."})
        snapshotFile.reload()
        root.refreshWatchlist()
        return
      }
      if (!root.watchlistResponseReceived && root.showingDetail && root.watchlistActionKey === Model.assetKey(root.detailAsset)) {
        if (root.watchlistAction !== "state" && root.watchlistBeforeAction)
          root.detailWatchlistState = root.watchlistBeforeAction
        root.watchlistMessage = "Request not confirmed. Refresh your watchlist before trying again."
      }
      root.watchlistBeforeAction = null
      if (root.watchlistAction !== "state") {
        root.refreshWatchlist()
        Qt.callLater(root.prepareWatchlistAction)
      }
    }
  }

  RefreshProcess {
    id: chartProc
    onExited: {
      if (root.chartProcSeq === root.chartSeq) root.detailLoading = false
    }
    onRunningChanged: {
      if (!running) {
        root.detailLoading = false
        root.detailPeriodChangeRequested = false
      }
    }
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
  }

  RefreshProcess {
    id: tickerProc
    stdinEnabled: true
    onStarted: {
      tickerProc.write(JSON.stringify(root.pendingTickerPayload || {}) + "\n")
      root.pendingTickerPayload = null
    }
    onExited: function(code) {
      root.acceptSnapshotReload = true
      snapshotFile.reload()
      if (code === 0) {
        root.searchQuery = ""
        root.searchResults = []
        root.listCursor = 0
        if (searchField) searchField.text = ""
        Qt.callLater(function() { root.refresh(false) })
      }
    }
  }

  RefreshProcess {
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
    interval: 10000
    running: root.opened
    repeat: true
    onTriggered: root.statusNow = Date.now()
  }

  Timer {
    // Keep an open dashboard current; the bar retains its slower cadence.
    // Failed refreshes still honor the helper's cooldown, without overlaps.
    interval: Model.snapshotNeedsRefresh(root.snapshot, root.statusNow) ? 5000 : 15000
    running: root.opened
    repeat: true
    onTriggered: {
      root.refresh()
      if (root.showingDetail && !chartProc.running)
        root.loadDetailChart(root.detailAsset)
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
      width: parent.width - Style.space(8) - (reorderHandle.visible ? reorderHandle.width + Style.space(8) : 0)
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      spacing: Style.space(2)

      Row {
        id: assetRowContent
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - rowSparkline.width - rowPrice.width - assetRowContent.spacing * 2
          spacing: Style.space(1)
          Row {
            id: assetNameRow
            width: parent.width
            spacing: Style.space(6)
            Text {
              width: parent.width - (assetPin.visible ? assetPin.width + assetNameRow.spacing : 0)
              text: String(modelData.name || modelData.id)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: !root.signedIn && root.isBarAsset(modelData)
              elide: Text.ElideRight
            }
            Text {
              id: assetPin
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
          id: rowSparkline
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
          id: rowPrice
          width: Style.space(92)
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: Number(modelData.price) > 0 ? Model.formatUsd(modelData.price, Number(modelData.price) >= 100 ? 2 : 4) : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: !modelData.watchlistUnavailable && isFinite(root.rowPeriodPercent(modelData)) ? Model.formatPercent(root.rowPeriodPercent(modelData)) : "—"
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
      onPositionChanged: function(mouse) {
        root.notePointerPosition(rowMouse.mapToItem(null, mouse.x, mouse.y))
        if (root.hoverSelectEnabled) root.listCursor = index
      }
      onClicked: root.chooseAsset(modelData)
    }

    Rectangle {
      id: reorderHandle
      visible: root.watchlistReorderView
      z: 3
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: Style.space(36)
      radius: Style.cornerRadius
      readonly property bool available: root.canReorderWatchlist && root.visibleAssets.length > 1
        && Model.watchlistItemKey(assetRow.modelData.watchlistItem) !== ""
      color: handleMouse.containsMouse && available ? Util.alpha(root.foreground, 0.1) : "transparent"
      Grid {
        anchors.centerIn: parent
        columns: 2
        spacing: Style.space(3)
        opacity: reorderHandle.available ? 1 : 0.4
        Repeater {
          model: 6
          Rectangle {
            width: Style.space(3)
            height: width
            radius: width / 2
            color: handleMouse.containsMouse ? root.foreground : root.muted
          }
        }
      }
      MouseArea {
        id: handleMouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: !reorderHandle.available ? Qt.ArrowCursor
          : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
        onPressed: function(mouse) {
          if (!reorderHandle.available) return
          flick.cancelFlick()
          root.watchlistDragRows = root.visibleAssets
          root.watchlistDragIndex = assetRow.index
          root.watchlistDropIndex = assetRow.index
          root.watchlistPressY = mapToItem(flick, mouse.x, mouse.y).y
          root.watchlistDragY = root.watchlistPressY
          root.listCursor = assetRow.index
          root.hoverSelectEnabled = false
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.updateWatchlistDrag(mapToItem(flick, mouse.x, mouse.y).y)
        }
        onReleased: function(mouse) {
          var point = mapToItem(flick, mouse.x, mouse.y)
          root.finishWatchlistDrag(point.x >= 0 && point.x <= flick.width && point.y >= 0 && point.y <= flick.height)
        }
        onCanceled: root.cancelWatchlistDrag()
      }
      Accessible.role: Accessible.Button
      Accessible.name: "Reorder " + String(assetRow.modelData.name || assetRow.modelData.id)
      Accessible.description: "Drag to reorder, or select the row and press Alt+Up or Alt+Down."
    }

    Rectangle {
      visible: root.watchlistDragging && root.watchlistDropIndex === assetRow.index
        && root.watchlistDropIndex !== root.watchlistDragIndex
      z: 4
      width: parent.width
      height: Math.max(2, Style.normalBorderWidth)
      y: root.watchlistDropIndex < root.watchlistDragIndex ? -Style.space(4) : parent.height + Style.space(4) - height
      radius: height / 2
      color: Color.accent
    }
    border.width: root.watchlistDragging && root.watchlistDragIndex === index ? Math.max(1, Style.normalBorderWidth) : 0
    border.color: Color.accent
  }

  component DetailMetricCard: Rectangle {
    id: metricCard
    required property var modelData

    width: parent ? (parent.width - Style.space(8)) / 2 : 0
    height: Style.space(62)
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, 0.035)
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Util.alpha(root.foreground, 0.09)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: String(metricCard.modelData.label || "")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: String(metricCard.modelData.value || "—")
        color: metricCard.modelData.accent ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
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
        enabled: root.canReorderWatchlist && root.watchlistDragIndex < 0 && !searchField.activeFocus
        sequence: "Alt+Up"
        context: Qt.WindowShortcut
        onActivated: root.moveWatchlistItem(root.listCursor, -1)
      }
      Shortcut {
        enabled: root.canReorderWatchlist && root.watchlistDragIndex < 0 && !searchField.activeFocus
        sequence: "Alt+Down"
        context: Qt.WindowShortcut
        onActivated: root.moveWatchlistItem(root.listCursor, 1)
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
        if (root.watchlistDragIndex >= 0) {
          root.cancelWatchlistDrag()
          event.accepted = true
        } else if (root.showingDetail) {
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

            MouseArea {
              id: detailBackArea
              visible: root.showingDetail
              anchors.left: parent.left
              anchors.right: detailActions.left
              anchors.rightMargin: Style.space(10)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              cursorShape: Qt.PointingHandCursor
              activeFocusOnTab: true
              Accessible.role: Accessible.Button
              Accessible.name: "Back to asset list"
              onClicked: root.closeDetail()
              Keys.onReturnPressed: root.closeDetail()
              Keys.onEnterPressed: root.closeDetail()
              Keys.onSpacePressed: root.closeDetail()
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
                id: watchlistButton
                visible: root.signedIn
                text: "Watchlist"
                iconText: Model.watchlistIsWatched(root.detailWatchlistState, root.detailAsset) ? "★" : "☆"
                enabled: !root.detailWatchlistState.ready || root.detailWatchlistState.canUpdate
                bordered: true
                focusable: true
                Accessible.name: Model.watchlistIsWatched(root.detailWatchlistState, root.detailAsset) ? "Remove from watchlist" : "Add to watchlist"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                iconSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: root.toggleWatchlist()
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
              label: "Sign in"
              primary: true
              enabled: !root.signingIn || root.loginPhase === "waiting"
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
            visible: !root.signedIn && root.loginStatus !== ""
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
                  width: parent.width
                  visible: root.showingDetail && root.watchlistMessage !== ""
                  text: root.watchlistMessage
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

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
                      visible: (root.showUpdating || (root.authLoading && root.sparkline.length < 2)) && !root.chartHover
                      text: root.authLoading ? "Loading details…" : "Updating…"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }

                Text {
                  width: parent.width
                  visible: !root.showingDetail && text !== ""
                  text: Model.freshnessText(root.snapshot, root.statusNow)
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  visible: !root.showingDetail && root.marketTab === "watchlist" && text !== ""
                  text: root.watchlistReorderMessage || root.watchlistStatus.error || ""
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
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
              interactive: contentHeight > height && root.watchlistDragIndex < 0
              flickableDirection: Flickable.VerticalFlick

              Column {
                id: detailBlock
                width: detailFlick.width
                spacing: Style.space(16)

                Column {
                  id: todaySection
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.showingDetail

                  Item {
                    width: parent.width
                    height: todayLabel.implicitHeight

                    Text {
                      id: todayLabel
                      anchors.left: parent.left
                      text: "TODAY"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.2
                    }

                    Rectangle {
                      anchors.left: todayLabel.right
                      anchors.leftMargin: Style.space(8)
                      anchors.right: parent.right
                      anchors.verticalCenter: todayLabel.verticalCenter
                      height: Math.max(1, Style.normalBorderWidth)
                      color: Util.alpha(root.foreground, 0.1)
                    }
                  }

                  Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)

                    Repeater {
                      model: root.detailIsCrypto
                        ? [
                            { label: "24H RANGE", value: root.detailRangeText() },
                            { label: "24H VOLUME", value: Number(detailChart.volume) > 0 ? Model.formatCompactUsd(detailChart.volume) : "—", accent: true }
                          ]
                        : [
                            { label: "OPEN", value: root.formatDetailPrice(detailChart.open) },
                            { label: "CLOSE", value: root.formatDetailPrice(detailChart.close) },
                            { label: "24H RANGE", value: root.detailRangeText() },
                            { label: "24H VOLUME", value: Number(detailChart.volume) > 0 ? Model.formatCompactUsd(detailChart.volume) : "—", accent: true }
                          ]
                      DetailMetricCard {}
                    }
                  }
                }

                Column {
                  id: marketDetailsSection
                  width: parent.width
                  visible: Array.isArray(detailChart.stats) && detailChart.stats.length > 0
                  spacing: Style.space(8)

                  Item {
                    width: parent.width
                    height: marketDetailsLabel.implicitHeight

                    Text {
                      id: marketDetailsLabel
                      anchors.left: parent.left
                      text: "MARKET DETAILS"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.2
                    }

                    Rectangle {
                      anchors.left: marketDetailsLabel.right
                      anchors.leftMargin: Style.space(8)
                      anchors.right: parent.right
                      anchors.verticalCenter: marketDetailsLabel.verticalCenter
                      height: Math.max(1, Style.normalBorderWidth)
                      color: Util.alpha(root.foreground, 0.1)
                    }
                  }

                  Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)

                    Repeater {
                      model: detailChart.stats || []
                      DetailMetricCard {}
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

              Rectangle {
                // A small preview follows the pointer without intercepting the drag.
                visible: root.watchlistDragging
                z: 10
                x: Style.space(8)
                y: root.watchlistDragY + flick.contentY - height / 2
                width: Math.min(flick.width - Style.space(56), dragLabel.implicitWidth + Style.space(24))
                height: Style.space(36)
                radius: Style.cornerRadius
                color: Color.background
                border.width: Math.max(1, Style.normalBorderWidth)
                border.color: Color.accent
                Text {
                  id: dragLabel
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  verticalAlignment: Text.AlignVCenter
                  text: root.watchlistDragIndex >= 0
                    ? String(root.visibleAssets[root.watchlistDragIndex].name || root.visibleAssets[root.watchlistDragIndex].id) : ""
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
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
                    text: root.marketTab === "watchlist"
                      ? (root.watchlistStatus.error ? "Watchlist unavailable."
                        : (!root.watchlistStatus.ready ? "Loading your Simple Retail watchlist…"
                          : (Number(root.watchlistStatus.unsupported || 0) > 0 ? "No supported watchlist items." : "Nothing on your Coinbase watchlist.")))
                      : "Nothing in this tab yet."
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: (!root.snapshotReady || root.authLoading) && root.visibleAssets.length === 0
                    text: root.authLoading ? "Loading your Coinbase portfolio…" : "Waiting for data. Retrying automatically…"
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
