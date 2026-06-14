package com.vucko.cruiserconnect.car

import android.app.Presentation
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.Surface
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Zeichnet die Cruise-Route als echte Karte auf die Android-Auto-Surface.
 *
 * 2026-06-14 (vucko K8): ECHTE MapLibre-Vektorkarte (Phone-Style cruise_dark)
 * statt des bisherigen handgemalten Gitters. Die androidx.car-Surface kann
 * keine View-Hierarchie hosten — der Google-dokumentierte Weg (auch von Mapbox
 * genutzt) ist ein VirtualDisplay aus der Car-Surface + eine Presentation, die
 * eine MapLibre-MapView rendert. Scheitert das Setup aus irgendeinem Grund,
 * fällt der Renderer GRACEFUL auf den bisherigen Canvas-Renderer zurück
 * (rote Linie auf dezentem Gitter) — niemals Crash.
 */
class CruiseCarMapSurfaceRenderer(
    private val context: Context,
    private val routeStore: CarRouteSnapshotStore,
) : SurfaceCallback {

    private val handler = Handler(Looper.getMainLooper())
    private var surfaceContainer: SurfaceContainer? = null
    private var visibleArea: Rect? = null

    // ── MapLibre-Pfad ───────────────────────────────────────────────────────
    private var useMapLibre = false
    private var virtualDisplay: android.hardware.display.VirtualDisplay? = null
    private var presentation: CarMapPresentation? = null
    private var lastRouteSignature: String? = null
    private var routeFitted = false

    // ── Canvas-Fallback-Zustand ─────────────────────────────────────────────
    private var zoomScale = 1.0f
    private var panX = 0f
    private var panY = 0f

    private val redrawRunnable = object : Runnable {
        override fun run() {
            if (useMapLibre) updateMapLibreRoute() else renderCanvas()
            handler.postDelayed(this, REDRAW_INTERVAL_MS)
        }
    }

    // MARK: - SurfaceCallback

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = surfaceContainer
        handler.removeCallbacks(redrawRunnable)
        val surface = surfaceContainer.surface
        useMapLibre = surface != null && tryStartMapLibre(
            surface,
            max(1, surfaceContainer.width),
            max(1, surfaceContainer.height),
            if (surfaceContainer.dpi > 0) surfaceContainer.dpi else 160,
        )
        // Egal welcher Pfad: der 1s-Loop hält Route/Kamera aktuell (K7-Throttle).
        handler.post(redrawRunnable)
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = Rect(visibleArea)
        if (!useMapLibre) renderCanvas()
    }

    override fun onStableAreaChanged(stableArea: Rect) {
        // Karte zeichnet in die volle Surface; Cards liegen im Stable-Bereich.
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        handler.removeCallbacks(redrawRunnable)
        teardownMapLibre()
        this.surfaceContainer = null
    }

    override fun onScroll(distanceX: Float, distanceY: Float) {
        if (useMapLibre) {
            // GestureDetector liefert die Strecke seit dem letzten Call als
            // alt−neu; negieren, damit die Karte dem Finger folgt (Drag-Gefühl).
            mapLibreMap()?.scrollBy(-distanceX, -distanceY)
            routeFitted = true // User hat selbst bewegt → kein Auto-Fit mehr
        } else {
            panX -= distanceX
            panY -= distanceY
            renderCanvas()
        }
    }

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        if (useMapLibre) {
            val zoomBy = (ln(scaleFactor.toDouble()) / ln(2.0))
            mapLibreMap()?.moveCamera(CameraUpdateFactory.zoomBy(zoomBy))
            routeFitted = true
        } else {
            zoomScale = (zoomScale * scaleFactor).coerceIn(MIN_ZOOM, MAX_ZOOM)
            renderCanvas()
        }
    }

    // MARK: - Öffentliche Steuerung (Map-Buttons)

    fun zoomIn() {
        if (useMapLibre) {
            mapLibreMap()?.moveCamera(CameraUpdateFactory.zoomIn()); routeFitted = true
        } else {
            zoomScale = (zoomScale * 1.4f).coerceIn(MIN_ZOOM, MAX_ZOOM); renderCanvas()
        }
    }

    fun zoomOut() {
        if (useMapLibre) {
            mapLibreMap()?.moveCamera(CameraUpdateFactory.zoomOut()); routeFitted = true
        } else {
            zoomScale = (zoomScale / 1.4f).coerceIn(MIN_ZOOM, MAX_ZOOM); renderCanvas()
        }
    }

    fun recenter() {
        if (useMapLibre) {
            routeFitted = false
            fitRouteIfPossible(routeStore.readSnapshot(), force = true)
        } else {
            zoomScale = 1.0f; panX = 0f; panY = 0f; renderCanvas()
        }
    }

    // MARK: - MapLibre (echte Karte)

    private fun mapLibreMap(): MapLibreMap? = presentation?.maplibreMap

    private fun tryStartMapLibre(surface: Surface, width: Int, height: Int, dpi: Int): Boolean {
        return try {
            MapLibre.getInstance(context)
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val vd = dm.createVirtualDisplay(
                "cc-car-map", width, height, dpi, surface,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY or
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION,
            ) ?: return false
            virtualDisplay = vd
            val pres = CarMapPresentation(context, vd.display)
            pres.show()
            presentation = pres
            lastRouteSignature = null
            routeFitted = false
            Log.i(TAG, "MapLibre car map started (${width}x$height @${dpi}dpi)")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "MapLibre car map setup failed — Canvas-Fallback", t)
            teardownMapLibre()
            false
        }
    }

    private fun teardownMapLibre() {
        runCatching { presentation?.dismissSafely() }
        presentation = null
        runCatching { virtualDisplay?.release() }
        virtualDisplay = null
        useMapLibre = false
    }

    /** Hält die Routenlinie aktuell + fittet beim ersten Mal die Kamera. */
    private fun updateMapLibreRoute() {
        val map = mapLibreMap() ?: return
        val style = map.style ?: return
        val snapshot = routeStore.readSnapshot()
        val sig = "${snapshot?.routeId ?: ""}|${snapshot?.coordinates?.size ?: 0}"
        if (sig != lastRouteSignature) {
            lastRouteSignature = sig
            val points = snapshot?.coordinates
                ?.filter { it.first != 0.0 || it.second != 0.0 }
                ?.map { Point.fromLngLat(it.first, it.second) }
                ?: emptyList()
            val source = style.getSourceAs<GeoJsonSource>(ROUTE_SOURCE)
            if (points.size >= 2) {
                source?.setGeoJson(LineString.fromLngLats(points))
                routeFitted = false
            } else {
                source?.setGeoJson(LineString.fromLngLats(emptyList<Point>()))
            }
        }
        if (!routeFitted) fitRouteIfPossible(snapshot, force = false)
    }

    private fun fitRouteIfPossible(snapshot: CarRouteSnapshot?, force: Boolean) {
        val map = mapLibreMap() ?: return
        val coords = snapshot?.coordinates ?: return
        if (coords.size < 2) return
        val builder = LatLngBounds.Builder()
        coords.forEach { builder.include(LatLng(it.second, it.first)) }
        val bounds = try { builder.build() } catch (_: Throwable) { return }
        runCatching {
            map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, FIT_PADDING_PX))
        }
        if (!force) routeFitted = true
    }

    /** Presentation, die eine MapLibre-MapView in den VirtualDisplay rendert. */
    private inner class CarMapPresentation(outer: Context, display: Display) :
        Presentation(outer, display) {
        var maplibreMap: MapLibreMap? = null
        private var mapView: MapView? = null

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            val options = MapLibreMapOptions().textureMode(true)
            val mv = MapView(context, options)
            mapView = mv
            setContentView(mv)
            mv.onCreate(null)
            mv.onStart()
            mv.onResume()
            mv.getMapAsync { map ->
                maplibreMap = map
                map.uiSettings.apply {
                    isLogoEnabled = false
                    isAttributionEnabled = false
                    isCompassEnabled = false
                    setAllGesturesEnabled(false) // Steuerung kommt über SurfaceCallback
                }
                map.setStyle(Style.Builder().fromUri(STYLE_URL)) { style ->
                    style.addSource(GeoJsonSource(ROUTE_SOURCE))
                    style.addLayer(
                        LineLayer(ROUTE_CASING_LAYER, ROUTE_SOURCE).withProperties(
                            PropertyFactory.lineColor(Color.argb(140, 0, 0, 0)),
                            PropertyFactory.lineWidth(11f),
                            PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                            PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                        ),
                    )
                    style.addLayer(
                        LineLayer(ROUTE_LAYER, ROUTE_SOURCE).withProperties(
                            PropertyFactory.lineColor(Color.rgb(255, 59, 48)),
                            PropertyFactory.lineWidth(6f),
                            PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                            PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                        ),
                    )
                    lastRouteSignature = null // erzwingt erstes Route-Update
                }
            }
        }

        fun dismissSafely() {
            runCatching { mapView?.onPause() }
            runCatching { mapView?.onStop() }
            runCatching { mapView?.onDestroy() }
            mapView = null
            maplibreMap = null
            runCatching { dismiss() }
        }
    }

    // MARK: - Canvas-Fallback (bisheriger Renderer)

    private fun renderCanvas() {
        val container = surfaceContainer ?: return
        val surface = container.surface ?: return
        if (!surface.isValid) return
        val canvas = tryLock(surface) ?: return
        try {
            drawRoute(canvas, routeStore.readSnapshot())
        } finally {
            runCatching { surface.unlockCanvasAndPost(canvas) }
        }
    }

    private fun tryLock(surface: Surface): Canvas? {
        return try {
            surface.lockCanvas(null)
        } catch (_: Exception) {
            null
        }
    }

    private fun drawRoute(canvas: Canvas, snapshot: CarRouteSnapshot?) {
        canvas.drawColor(Color.rgb(11, 16, 23))
        drawGrid(canvas)
        if (snapshot == null || !snapshot.hasRoute) return

        val coordinates = snapshot.coordinates
        val minLng = coordinates.minOf { it.first }
        val maxLng = coordinates.maxOf { it.first }
        val minLat = coordinates.minOf { it.second }
        val maxLat = coordinates.maxOf { it.second }
        val lngSpan = max(0.0001, maxLng - minLng)
        val latSpan = max(0.0001, maxLat - minLat)
        val centerLng = (minLng + maxLng) / 2.0
        val centerLat = (minLat + maxLat) / 2.0

        val safe = visibleArea ?: Rect(0, 0, canvas.width, canvas.height)
        val padding = 56f
        val width = max(1f, safe.width() - padding * 2)
        val height = max(1f, safe.height() - padding * 2)
        val baseScale = min(width / lngSpan.toFloat(), height / latSpan.toFloat())
        val scale = baseScale * zoomScale
        val cx = safe.exactCenterX() + panX
        val cy = safe.exactCenterY() + panY

        fun x(lng: Double): Float = cx + ((lng - centerLng) * scale).toFloat()
        fun y(lat: Double): Float = cy + ((centerLat - lat) * scale).toFloat()

        val routeWidth = max(8f, min(canvas.width, canvas.height) * 0.018f)
        val glowWidth = routeWidth * 2.4f

        val path = Path()
        coordinates.forEachIndexed { index, coordinate ->
            val px = x(coordinate.first)
            val py = y(coordinate.second)
            if (index == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }

        val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = glowWidth
            color = Color.argb(88, 255, 59, 48)
        }
        val routePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = routeWidth
            color = Color.rgb(255, 59, 48)
        }
        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, routePaint)

        val start = coordinates.first()
        val end = coordinates.last()
        val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.WHITE
        }
        val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.rgb(53, 132, 243)
        }
        canvas.drawCircle(x(start.first), y(start.second), routeWidth * 0.9f, markerPaint)
        canvas.drawCircle(x(end.first), y(end.second), routeWidth * 1.05f, accentPaint)
        canvas.drawCircle(x(end.first), y(end.second), routeWidth * 0.62f, markerPaint)
    }

    private fun drawGrid(canvas: Canvas) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(42, 255, 255, 255)
            strokeWidth = 1.2f
        }
        val step = max(90f, min(canvas.width, canvas.height) / 6f)
        var x = 0f
        while (x <= canvas.width) {
            canvas.drawLine(x, 0f, x, canvas.height.toFloat(), paint)
            x += step
        }
        var y = 0f
        while (y <= canvas.height) {
            canvas.drawLine(0f, y, canvas.width.toFloat(), y, paint)
            y += step
        }
    }

    companion object {
        private const val TAG = "CruiseCarMap"
        private const val REDRAW_INTERVAL_MS = 1000L // K7: 2500→1000
        private const val MIN_ZOOM = 0.4f
        private const val MAX_ZOOM = 8.0f
        private const val FIT_PADDING_PX = 64
        // Gleicher Phone-Vektor-Style wie iOS CarPlay (PMTiles, MapLibre liest pmtiles nativ).
        private const val STYLE_URL = "https://tiles.cruiseconnector.at/cruise_dark.json"
        private const val ROUTE_SOURCE = "cc-route"
        private const val ROUTE_LAYER = "cc-route-line"
        private const val ROUTE_CASING_LAYER = "cc-route-casing"
    }
}
