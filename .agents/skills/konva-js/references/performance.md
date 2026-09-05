# Performance

Konva is fast, but canvas drawing and filters can become expensive at scale. These guidelines keep apps smooth.

## Layering Strategy

1. Put static content (backgrounds, grids) on separate layers and draw them once.
2. Put interactive content on its own layer and use `batchDraw()` to schedule redraws.
3. Put UI overlays (tooltips, selection) on a top layer.

Example:

```js
const bg = new Konva.Layer({ listening: false }); // no events
const main = new Konva.Layer();
const ui = new Konva.Layer();
stage.add(bg, main, ui);
```

## Caching

- Call `node.cache()` for complex shapes, shapes with shadows, or when applying filters.
- Call `node.clearCache()` before making frequent geometry changes.
- Use `cache({ pixelRatio })` to control cache resolution for performance/quality tradeoff.

## Hit Graph Optimization

- Disable hit graph on non-interactive layers: `layer.listening(false)`.
- Disable on shapes that never need events: `shape.listening(false)`.
- Avoid `getAllIntersections()` in tight loops.

## Pixel Ratio

Set `Konva.pixelRatio` BEFORE creating stages if you need to target a specific devicePixelRatio. Lowering pixel ratio improves performance but reduces crispness on high-DPI displays.

```js
Konva.pixelRatio = 1; // default auto
```

## Batch Drawing

- Use `layer.batchDraw()` instead of `layer.draw()` when making multiple updates per frame.
- For animations, draw only layers that changed.

## Avoid Frequent DOM Access

If you need pointer coordinates for things outside Konva events, prefer `stage.getPointerPosition()` or `stage.setPointersPositions(event)` rather than querying DOM frequently.

## Use `listening(false)` Instead of `hitGraphEnabled`

The `hitGraphEnabled` API is deprecated; prefer `layer.listening(false)`.

## Memory Management

- Call `node.destroy()` when shapes are no longer needed.
- Use `Konva.releaseCanvasOnDestroy = true` on Safari to avoid leaks.

## Profiling

Use Chrome DevTools Performance panel and profile canvas paints. Measure `layer.draw()` times when troubleshooting.
