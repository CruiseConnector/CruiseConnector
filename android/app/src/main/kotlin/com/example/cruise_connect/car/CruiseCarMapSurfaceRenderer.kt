package com.vucko.cruiserconnect.car

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import kotlin.math.max
import kotlin.math.min

/**
 * Zeichnet die Cruise-Route als interaktive Karte auf die Android-Auto-Surface.
 *
 * 2026-06-02 (vucko): Aus dem statischen Hintergrund-Renderer wurde eine
 * bedienbare Karte im Maps-Stil:
 *  - Zoom rein/raus + Zentrieren ([zoomIn]/[zoomOut]/[recenter]) — vom
 *    NavigationScreen über die Map-Buttons aufgerufen.
 *  - Schieben (Pan) per Finger ([onScroll]) und Pinch-Zoom ([onScale]).
 *  - periodisches Neuzeichnen, damit Reroutes/POIs automatisch erscheinen.
 */
class CruiseCarMapSurfaceRenderer(
    private val routeStore: CarRouteSnapshotStore,
) : SurfaceCallback {

    private val handler = Handler(Looper.getMainLooper())
    private var surfaceContainer: SurfaceContainer? = null
    private var visibleArea: Rect? = null

    private var zoomScale = 1.0f
    private var panX = 0f
    private var panY = 0f

    private val redrawRunnable = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, REDRAW_INTERVAL_MS)
        }
    }

    // MARK: - SurfaceCallback

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = surfaceContainer
        handler.removeCallbacks(redrawRunnable)
        handler.post(redrawRunnable)
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = Rect(visibleArea)
        render()
    }

    override fun onStableAreaChanged(stableArea: Rect) {
        // Karte zeichnet in die volle Surface; Cards liegen im Stable-Bereich.
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        handler.removeCallbacks(redrawRunnable)
        this.surfaceContainer = null
    }

    override fun onScroll(distanceX: Float, distanceY: Float) {
        panX -= distanceX
        panY -= distanceY
        render()
    }

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        zoomScale = (zoomScale * scaleFactor).coerceIn(MIN_ZOOM, MAX_ZOOM)
        render()
    }

    // MARK: - Öffentliche Steuerung (Map-Buttons)

    fun zoomIn() {
        zoomScale = (zoomScale * 1.4f).coerceIn(MIN_ZOOM, MAX_ZOOM)
        render()
    }

    fun zoomOut() {
        zoomScale = (zoomScale / 1.4f).coerceIn(MIN_ZOOM, MAX_ZOOM)
        render()
    }

    fun recenter() {
        zoomScale = 1.0f
        panX = 0f
        panY = 0f
        render()
    }

    // MARK: - Zeichnen

    private fun render() {
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
        private const val REDRAW_INTERVAL_MS = 2500L
        private const val MIN_ZOOM = 0.4f
        private const val MAX_ZOOM = 8.0f
    }
}
