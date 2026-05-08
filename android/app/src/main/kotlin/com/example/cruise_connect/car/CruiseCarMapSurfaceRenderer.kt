package com.example.cruise_connect.car

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.view.Surface
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import kotlin.math.max
import kotlin.math.min

class CruiseCarMapSurfaceRenderer(
    private val routeStore: CarRouteSnapshotStore,
) : SurfaceCallback {
    private var visibleArea: Rect? = null

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        render(surfaceContainer)
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = Rect(visibleArea)
    }

    override fun onStableAreaChanged(stableArea: Rect) {
        // The renderer draws into the full host surface. Templates keep cards
        // inside the stable area; the route is intentionally background-only.
    }

    private fun render(surfaceContainer: SurfaceContainer) {
        val surface = surfaceContainer.surface ?: return
        if (!surface.isValid) return
        val canvas = tryLock(surface) ?: return
        try {
            drawRoute(canvas, routeStore.readSnapshot())
        } finally {
            surface.unlockCanvasAndPost(canvas)
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
        val safe = visibleArea ?: Rect(0, 0, canvas.width, canvas.height)
        val padding = 56f
        val width = max(1f, safe.width().toFloat() - padding * 2)
        val height = max(1f, safe.height().toFloat() - padding * 2)
        val scale = min(width / lngSpan.toFloat(), height / latSpan.toFloat())
        val routeWidth = max(8f, min(canvas.width, canvas.height) * 0.018f)
        val glowWidth = routeWidth * 2.4f

        fun x(lng: Double): Float {
            val routeWidthPx = lngSpan.toFloat() * scale
            val left = safe.left + (safe.width() - routeWidthPx) / 2f
            return left + ((lng - minLng).toFloat() * scale)
        }

        fun y(lat: Double): Float {
            val routeHeightPx = latSpan.toFloat() * scale
            val top = safe.top + (safe.height() - routeHeightPx) / 2f
            return top + ((maxLat - lat).toFloat() * scale)
        }

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
}
