# Stage and Layer Reference

## Konva.Stage

The root container. A stage is attached to a DOM element and contains one or more layers.

### Creation

```js
// By element ID
const stage = new Konva.Stage({
  container: 'containerId',  // or '#containerId', '.containerClass'
  width: 800,
  height: 600,
});

// By DOM element
const stage = new Konva.Stage({
  container: document.getElementById('container'),
  width: window.innerWidth,
  height: window.innerHeight,
});
```

### Properties

```js
// Container
stage.container();                    // get DOM element
stage.container(newContainerElement); // set DOM element

// Size
stage.width();    // get width
stage.width(1024); // set width
stage.height();
stage.height(768);
stage.setSize({ width: 1024, height: 768 });

// Pointer
stage.getPointerPosition();  // { x, y } or null
stage.getPointerPositions(); // for multi-touch: [{ id, x, y }, ...]
```

### Methods

```js
// Layers
stage.getLayers();           // array of layers
stage.add(layer);            // add a layer
stage.draw();                // redraw all layers
stage.clear();               // clear all layers
stage.batchDraw();           // batch draw all layers

// Hit detection
const shape = stage.getIntersection({ x: 100, y: 200 });
// Optional: pass selector to find ancestor
const group = stage.getIntersection({ x: 100, y: 200 }, (node) =>
  node.hasName('selectable')
);

// Manual pointer registration (for external events)
stage.setPointersPositions(event);

// Destroy
stage.destroy();  // cleans up everything
```

### Responsive Stage

```js
function resizeStage() {
  const container = document.getElementById('container');
  stage.width(container.offsetWidth);
  stage.height(container.offsetHeight);
  stage.batchDraw();
}

window.addEventListener('resize', resizeStage);
```

---

## Konva.Layer

Each layer is a separate `<canvas>` element. Layers are used to contain groups or shapes.

### Creation

```js
const layer = new Konva.Layer();
stage.add(layer);

// With options
const layer = new Konva.Layer({
  clearBeforeDraw: true,     // clear canvas before each draw (default)
  imageSmoothingEnabled: true,
  clip: { x: 0, y: 0, width: 500, height: 500 },
});
```

### Properties

```js
layer.width();    // returns stage width (setter does nothing)
layer.height();   // returns stage height (setter does nothing)
layer.getCanvas();
layer.getNativeCanvasElement();  // raw HTMLCanvasElement
layer.getHitCanvas();
layer.getContext();              // Konva.Context wrapper
```

### Methods

```js
// Drawing
layer.draw();        // immediate redraw
layer.batchDraw();   // schedule redraw for next requestAnimationFrame
layer.clear();       // clear this layer only

// Hit graph
layer.listening(true);   // enable hit graph (recommended)
layer.listening(false);  // disable hit graph (performance boost)

// Debug: toggle hit canvas overlay
layer.toggleHitCanvas();

// Adding content
layer.add(shape);
layer.add(group);

// Batch draw is preferred for animations
function animate() {
  shape.rotation(shape.rotation() + 1);
  layer.batchDraw();
  requestAnimationFrame(animate);
}
```

### Multiple Layers Strategy

```js
// Background layer (rarely changes, no events)
const bgLayer = new Konva.Layer();
bgLayer.listening(false);  // skip hit graph for performance
stage.add(bgLayer);

// Main interactive layer
const mainLayer = new Konva.Layer();
stage.add(mainLayer);

// Overlay/UI layer (on top)
const uiLayer = new Konva.Layer();
stage.add(uiLayer);

// Only redraw what changed
bgLayer.draw();       // once at init
mainLayer.batchDraw(); // during interactions
```

### Clipping

```js
// Clip layer to a region
layer.clip({ x: 0, y: 0, width: 400, height: 300 });

// Individual properties
layer.clipX(10);
layer.clipY(10);
layer.clipWidth(200);
layer.clipHeight(200);

// Custom clip function
layer.clipFunc((ctx) => {
  ctx.beginPath();
  ctx.arc(200, 200, 100, 0, Math.PI * 2);
  ctx.closePath();
});
```

---

## Konva.Group

Container for shapes or other groups. Groups support transforms, nesting, and events.

```js
const group = new Konva.Group({
  x: 100,
  y: 100,
  rotation: 30,
  draggable: true,
});

group.add(rect);
group.add(circle);
group.add(text);

layer.add(group);
```

### Group Methods

```js
// Children
group.getChildren();
group.getChildren((child) => child.name() === 'foo');
group.hasChildren();
group.removeChildren();    // remove without destroying
group.destroyChildren();   // remove AND destroy

// Find within group
group.findOne('#myShape');
group.find('.highlighted');

// Check ancestry
group.isAncestorOf(shape);
```

### Nested Groups

```js
const outer = new Konva.Group({ x: 50, y: 50 });
const inner = new Konva.Group({ x: 20, y: 20 });
const shape = new Konva.Rect({ x: 0, y: 0, width: 50, height: 50 });

inner.add(shape);
outer.add(inner);
layer.add(outer);

// shape absolute position = outer + inner + shape
// = (50+20+0, 50+20+0) = (70, 70)
```

### Group Clipping

```js
const clippedGroup = new Konva.Group({
  clip: { x: 0, y: 0, width: 200, height: 200 },
});
// Only children within clip region are visible
```

---

## Konva.FastLayer

**DEPRECATED.** Use `Konva.Layer({ listening: false })` instead.

FastLayer renders ~2x faster than normal layers because it skips hit graph and event handling. Use it for static backgrounds or decorative elements that don't need interaction.

```js
// Modern equivalent:
const fastLayer = new Konva.Layer({ listening: false });
```

---

## Hit Graph

Konva maintains a separate "hit canvas" for each layer. When you click, Konva checks the hit canvas pixel color to determine which shape was clicked.

```js
// Each shape gets a unique color on the hit canvas
// Invisible shapes still need to be drawn on hit canvas for events

// Disable hit graph for non-interactive layers
layer.listening(false);

// Disable for individual shapes
shape.listening(false);

// Re-enable
layer.listening(true);
shape.listening(true);
```

### Hit Graph Performance Tips

1. **Disable on decoration layers** — `layer.listening(false)` for backgrounds
2. **Disable on individual shapes** that don't need events
3. **Use `batchDraw()`** to avoid redundant hit canvas redraws
4. **Avoid `getAllIntersections()`** — it's O(n) and clears a temp canvas

---

## Canvas Management

```js
// Get raw canvas elements
const sceneCanvas = layer.getCanvas()._canvas;
const hitCanvas = layer.getHitCanvas()._canvas;

// Get 2d contexts
const sceneCtx = layer.getContext()._context;
```
