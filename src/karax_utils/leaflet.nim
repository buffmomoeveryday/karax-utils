## Typed Leaflet wrapper for Karax (JS backend).
##
## Pattern: typed Nim config → thin `importjs` → opaque handles.
## App code stays typed; it does not poke `L.*` option bags.
##
##   import karax_utils/[leaflet, lifecycle]
##
##   var map: LeafletMap
##
##   proc mapView(): VNode =
##     onMount("map"):
##       loadLeaflet().then(proc() =
##         mountMap("map-el", defaultMapConfig(latLng(27.7172, 85.3240), 13),
##           proc(m: LeafletMap) =
##             map = m
##             discard m.addMarker(latLng(27.7172, 85.3240), "Kathmandu")
##         )
##       )
##     onDestroy("map"):
##       map.destroy()
##       map = nil
##     buildHtml(tdiv(id = "map-el", class = "h-80 w-full"))
##
## Needs Leaflet on the page (`loadLeaflet` CDN, or your own tags).

import std/jsffi
import karax/kdom
import karax_utils/jsbind
export jsbind

type
  LatLng* = object
    lat*, lng*: float

  MapConfig* = object
    center*: LatLng
    zoom*: int
    tileUrl*: string
    attribution*: string

  ## Opaque JS handles — methods via importjs only.
  LeafletMap* = ref object
  LeafletMarker* = ref object
  LeafletTileLayer* = ref object

const
  defaultLeafletVersion* = "1.9.4"
  defaultOsmTiles* = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
  defaultOsmAttr* =
    """&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>"""

proc latLng*(lat, lng: float): LatLng =
  LatLng(lat: lat, lng: lng)

proc defaultMapConfig*(center = latLng(0, 0), zoom = 2): MapConfig =
  MapConfig(
    center: center, zoom: zoom, tileUrl: defaultOsmTiles, attribution: defaultOsmAttr
  )

# ---------------------------------------------------------------------------
# CDN
# ---------------------------------------------------------------------------

proc loadLeaflet*(version = defaultLeafletVersion): JsPromise =
  ## Inject Leaflet CSS + JS once. Await with `.then` before `mountMap`.
  loadCss(cstring("https://unpkg.com/leaflet@" & version & "/dist/leaflet.css"))
  loadScript(cstring("https://unpkg.com/leaflet@" & version & "/dist/leaflet.js"))

# ---------------------------------------------------------------------------
# Low-level FFI
# ---------------------------------------------------------------------------
when defined js:
  proc lMap(el: Node): LeafletMap {.importjs: "L.map(#)".}
  proc lSetView(
    m: LeafletMap, lat, lng: float, zoom: int
  ): LeafletMap {.importjs: "#.setView([#, #], #)".}

  proc lTileLayer(
    url: cstring, opts: JsObject
  ): LeafletTileLayer {.importjs: "L.tileLayer(#, #)".}

  proc lMarker(lat, lng: float): LeafletMarker {.importjs: "L.marker([#, #])".}
  proc lBindPopup(
    marker: LeafletMarker, html: cstring
  ): LeafletMarker {.importjs: "#.bindPopup(#)".}

  proc lRemove(m: LeafletMap) {.importjs: "#.remove()".}
  proc lInvalidateSize(m: LeafletMap) {.importjs: "#.invalidateSize()".}
  proc lFlyTo(
    m: LeafletMap, lat, lng: float, zoom: int
  ) {.importjs: "#.flyTo([#, #], #)".}

  proc addTo(
    layer: LeafletTileLayer, m: LeafletMap
  ): LeafletTileLayer {.importjs: "#.addTo(#)".}

  proc addTo(
    marker: LeafletMarker, m: LeafletMap
  ): LeafletMarker {.importjs: "#.addTo(#)".}

  proc getElementById(id: cstring): Node {.importjs: "document.getElementById(#)".}
  proc setTimeout(cb: proc(), ms: int): int {.importjs: "setTimeout(#, #)".}

  # ---------------------------------------------------------------------------
  # High-level Nim API
  # ---------------------------------------------------------------------------

  proc mountMap*(el: Node, cfg: MapConfig): LeafletMap =
    ## Create a map in `el`, set view, add tile layer.
    doAssert not el.isNil, "mountMap: element is nil"
    result = lMap(el)
    discard result.lSetView(cfg.center.lat, cfg.center.lng, cfg.zoom)
    var opts = newJsObject()
    opts["attribution"] = toJs(cfg.attribution)
    discard lTileLayer(cstring(cfg.tileUrl), opts).addTo(result)

  proc mountMap*(elId: cstring, cfg: MapConfig, onReady: proc(m: LeafletMap)) =
    ## Wait until `#elId` exists (Karax may patch DOM after `onMount`), then mount.
    var tries = 0
    proc tick() =
      let el = getElementById(elId)
      if el.isNil:
        inc tries
        if tries < 60:
          discard setTimeout(tick, 16)
        return
      onReady(mountMap(el, cfg))

    discard setTimeout(tick, 0)

  proc destroy*(m: LeafletMap) =
    ## Tear down the map — call from `onDestroy`.
    if not m.isNil:
      m.lRemove()

  proc invalidateSize*(m: LeafletMap) =
    if not m.isNil:
      m.lInvalidateSize()

  proc flyTo*(m: LeafletMap, pos: LatLng, zoom: int) =
    if not m.isNil:
      m.lFlyTo(pos.lat, pos.lng, zoom)

  proc setView*(m: LeafletMap, pos: LatLng, zoom: int) =
    if not m.isNil:
      discard m.lSetView(pos.lat, pos.lng, zoom)

  proc addMarker*(m: LeafletMap, pos: LatLng, popup = ""): LeafletMarker =
    result = lMarker(pos.lat, pos.lng)
    if popup.len > 0:
      discard result.lBindPopup(cstring(popup))
    discard result.addTo(m)
