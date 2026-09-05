---
name: konva-js
description: >
  Use Konva.js for 2D HTML5 Canvas graphics with shapes, animations, events, drag-and-drop,
  filters, and serialization. Trigger this skill whenever the user mentions Konva, konva-js,
  react-konva, vue-konva, svelte-konva, ng2-konva, canvas graphics, canvas shapes, canvas
  editor, interactive canvas, canvas drag-and-drop, canvas animations, canvas filters,
  canvas serialization, Transformer tool, or wants to build a canvas-based application
  (diagram editor, whiteboard, floor plan, seat map, image annotation tool, design tool).
  Also use when the user needs an object-oriented canvas library with event handling,
  hit detection, or framework-specific canvas components (React, Vue, Svelte, Angular).
  If the user is working with HTML5 Canvas and mentions shapes, layers, stages, or any
  canvas manipulation beyond basic 2D context drawing, use this skill.
---

# Konva.js

Konva.js is an open-source 2D HTML5 Canvas JavaScript framework that provides an object-oriented API for canvas graphics. It uses a **Stage → Layer → Group → Shape** hierarchy. You create a Stage (attached to a DOM container), add Layers (each is a separate `<canvas>` element), and draw Shapes on those layers.

**Install:** `npm install konva` (plus `react-konva`, `vue-konva`, `svelte-konva`, or `ng2-konva` for framework bindings)

## Quick Start

```js
import Konva from 'konva';

const stage = new Konva.Stage({
  container: 'container', // DOM element id or selector
  width: window.innerWidth,
  height: window.innerHeight,
});

const layer = new Konva.Layer();
stage.add(layer);

const rect = new Konva.Rect({
  x: 50, y: 50, width: 100, height: 50,
  fill: 'red', stroke: 'black', strokeWidth: 2,
  draggable: true,
});
layer.add(rect);
layer.draw();
```

## Core Concepts

### Hierarchy

| Level | Class | Purpose |
|-------|-------|---------|
| Stage | `Konva.Stage` | Root container, attached to DOM |
| Layer | `Konva.Layer` | Canvas element, holds groups/shapes |
| Group | `Konva.Group` | Container for shapes, supports transforms |
| Shape | `Konva.Rect`, `Konva.Circle`, etc. | Drawable primitives |

### Node Properties (all shapes inherit)

Every node supports: `x`, `y`, `width`, `height`, `rotation`, `scaleX`, `scaleY`, `skewX`, `skewY`, `opacity`, `visible`, `listening`, `draggable`, `name`, `id`, `offsetX`, `offsetY`.

### Transforms

```js
node.position({ x: 100, y: 200 });
node.rotation(45);          // degrees
node.scale({ x: 2, y: 2 });
node.offsetX(50);           // rotation/scale center
```

## Shapes

| Shape | Key Props | Description |
|-------|-----------|-------------|
| `Rect` | `width`, `height`, `cornerRadius` | Rectangle with optional rounded corners |
| `Circle` | `radius` | Circle |
| `Ellipse` | `radius: { x, y }` | Ellipse |
| `Line` | `points: [x1,y1,x2,y2,...]`, `tension`, `closed`, `bezier` | Polyline, spline, or polygon |
| `Arrow` | `points`, `pointerLength`, `pointerWidth`, `pointerAtBeginning`, `pointerAtEnding` | Line with arrowhead |
| `Text` | `text`, `fontSize`, `fontFamily`, `fontStyle`, `align`, `lineHeight`, `wrap`, `ellipsis` | Multi-line text |
| `TextPath` | `text`, `data` (SVG path) | Text along a path |
| `Image` | `image` (HTMLImageElement), `crop`, `cropX`, `cropY`, `cropWidth`, `cropHeight` | Raster image |
| `Path` | `data` (SVG path string) | SVG path shape |
| `Star` | `numPoints`, `innerRadius`, `outerRadius` | Star polygon |
| `RegularPolygon` | `sides`, `radius`, `cornerRadius` | Triangle, hexagon, etc. |
| `Ring` | `innerRadius`, `outerRadius` | Donut shape |
| `Arc` | `angle`, `innerRadius`, `outerRadius`, `clockwise` | Arc segment |
| `Wedge` | `angle`, `radius`, `clockwise` | Pie slice |
| `Label` | Contains `Text` + `Tag` children | Speech bubble / label |
| `Tag` | `pointerDirection`, `pointerWidth`, `pointerHeight`, `cornerRadius` | Label pointer background |
| `Sprite` | `image`, `animations`, `animation`, `frameRate`, `frameIndex` | Sprite sheet animation |
| `Shape` (custom) | `sceneFunc`, `hitFunc` | Custom drawn shape |

### Custom Shape Example

```js
const custom = new Konva.Shape({
  sceneFunc(ctx, shape) {
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(100, 50);
    ctx.lineTo(50, 100);
    ctx.closePath();
    ctx.fillStrokeShape(shape);
  },
  fill: 'blue',
  stroke: 'black',
  strokeWidth: 2,
});
```

## Styling

All shapes support:

```js
// Fill
fill: 'red',                                    // Solid color
fillLinearGradientStartPoint: { x: 0, y: 0 },   // Linear gradient
fillLinearGradientEndPoint: { x: 100, y: 100 },
fillLinearGradientColorStops: [0, 'red', 1, 'blue'],
fillRadialGradientStartPoint: { x: 50, y: 50 }, // Radial gradient
fillRadialGradientStartRadius: 0,
fillRadialGradientEndPoint: { x: 50, y: 50 },
fillRadialGradientEndRadius: 50,
fillRadialGradientColorStops: [0, 'red', 1, 'blue'],
fillPatternImage: imageObj,                     // Pattern fill
fillPatternRepeat: 'no-repeat',

// Stroke
stroke: 'black',
strokeWidth: 2,
strokeLinearGradientColorStops: [...],          // Gradient stroke
dash: [10, 5],                                  // Dashed
dashEnabled: true,
lineCap: 'round',                               // butt, round, square
lineJoin: 'round',                              // miter, round, bevel

// Shadow
shadowColor: 'black',
shadowBlur: 10,
shadowOffset: { x: 5, y: 5 },
shadowOpacity: 0.5,

// Opacity & composite
opacity: 0.8,
globalCompositeOperation: 'source-over',
```

## Events

```js
shape.on('click', (e) => { /* clicked */ });
shape.on('mouseenter mouseleave', (e) => { /* hover */ });
shape.on('dragstart dragmove dragend', (e) => { /* drag */ });
shape.on('tap dbltap', (e) => { /* touch */ });
shape.on('contextmenu', (e) => { /* right click */ });

// Namespace events
shape.on('click.myNamespace', handler);
shape.off('.myNamespace'); // remove all in namespace

// Event delegation on stage/layer
stage.on('click', (e) => {
  const shape = e.target; // clicked shape
});

// Get pointer position
const pos = stage.getPointerPosition();
```

Supported events: `click`, `dblclick`, `mousedown`, `mouseup`, `mousemove`, `mouseenter`, `mouseleave`, `mouseover`, `mouseout`, `wheel`, `contextmenu`, `touchstart`, `touchmove`, `touchend`, `tap`, `dbltap`, `dragstart`, `dragmove`, `dragend`.

## Drag and Drop

```js
const shape = new Konva.Rect({
  draggable: true,
  dragDistance: 3, // minimum pixels before drag starts
  dragBoundFunc(pos) {
    // Constrain dragging
    return {
      x: Math.max(0, Math.min(pos.x, stage.width() - this.width())),
      y: Math.max(0, Math.min(pos.y, stage.height() - this.height())),
    };
  },
});
```

## Animations & Tweens

### Frame-based Animation

```js
const anim = new Konva.Animation((frame) => {
  const dist = 50 * (frame.timeDiff / 1000); // pixels/sec
  node.move({ x: dist, y: 0 });
}, layer);
anim.start();
anim.stop();
```

### Tween

```js
import Konva from 'konva';

const tween = new Konva.Tween({
  node: shape,
  duration: 1,
  easing: Konva.Easings.EaseInOut,
  x: 200,
  rotation: 360,
  fill: 'red',
  onUpdate: () => {},
  onFinish: () => {},
});

tween.play();
tween.pause();
tween.reverse();
tween.reset();
```

### Short-form `to()`

```js
shape.to({ x: 200, duration: 0.5, easing: Konva.Easings.EaseOut });
```

## Transformer (Select & Transform)

```js
const transformer = new Konva.Transformer({
  nodes: [selectedShape],
  enabledAnchors: ['top-left', 'top-right', 'bottom-left', 'bottom-right'],
  rotateEnabled: true,
  keepRatio: true,
  centeredScaling: false,
});
layer.add(transformer);

// Update when selection changes
transformer.nodes([newShape]);
transformer.forceUpdate();

// Events
transformer.on('transform', () => {});
transformer.on('transformstart', () => {});
transformer.on('transformend', () => {});
```

## Filters

```js
// Apply filters to an image
image.filters([Konva.Filters.Blur, Konva.Filters.Brighten]);
image.blurRadius(10);
image.brightness(0.2);

// Must cache after setting filters
image.cache();
```

Available filters: `Blur`, `Brighten`, `Brightness`, `Contrast`, `Emboss`, `Enhance`, `Grayscale`, `HSL`, `HSV`, `Invert`, `Mask`, `Noise`, `Pixelate`, `Posterize`, `RGB`, `RGBA`, `Sepia`, `Solarize`, `Threshold`.

## Caching & Performance

```js
// Cache complex shapes for better performance
shape.cache();
shape.clearCache();

// Batch draws
layer.batchDraw(); // schedules draw for next frame

// Disable hit graph for non-interactive layers
layer.listening(false);

// Use pixel ratio wisely
Konva.pixelRatio = 1; // force 1x for performance

// Global settings
Konva.autoDrawEnabled = true;    // auto-update canvas (default)
Konva.dragDistance = 3;          // drag threshold
Konva.showWarnings = true;       // show warnings
```

## Serialization

```js
// Save stage to JSON
const json = stage.toJSON();

// Restore from JSON
const stage = Konva.Node.create(json, 'container');

// Export to image
const dataURL = stage.toDataURL({ mimeType: 'image/png', pixelRatio: 2 });
stage.toBlob((blob) => { /* upload blob */ });
stage.toImage({ pixelRatio: 2 }, (img) => { /* img is HTMLImageElement */ });
```

## Hit Detection

```js
// Get shape at point
const shape = stage.getIntersection({ x: 100, y: 200 });

// Get all shapes at point (container method, slower)
const shapes = layer.getAllIntersections({ x: 100, y: 200 });

// Custom hit area
shape.hitFunc((ctx) => {
  ctx.beginPath();
  ctx.arc(0, 0, 50, 0, Math.PI * 2);
  ctx.fillStrokeShape(shape);
});
```

## Reference Files

Read these for detailed guidance:

- [references/shapes.md](references/shapes.md) — All shape constructors, props, and examples
- [references/node-api.md](references/node-api.md) — Node methods: find, traverse, clone, destroy, toObject, toJSON
- [references/stage-layer.md](references/stage-layer.md) — Stage and Layer configuration, batch drawing, hit graphs
- [references/react-konva.md](references/react-konva.md) — react-konva integration patterns
- [references/animations-tweens.md](references/animations-tweens.md) — Animation and Tween details, easing functions
- [references/filters.md](references/filters.md) — Filter usage, parameters, and combinations
- [references/performance.md](references/performance.md) — Performance optimization, caching, hit graph tuning
- [references/serialization.md](references/serialization.md) — toJSON, fromJSON, export, node creation

## Best Practices

1. **One layer per logical group** — separate interactive shapes from background, use multiple layers to minimize redraws
2. **Cache complex or filtered shapes** — call `cache()` after setup, `clearCache()` before changing shape geometry
3. **Use `batchDraw()`** for rapid updates — schedules draw on next animation frame instead of immediate
4. **Disable hit graphs on decoration layers** — `layer.listening(false)` for layers that don't need events
5. **Use Transformer for resize/rotate** — don't build custom transform handles
6. **Prefer `find()` and `findOne()` with selectors** — `stage.findOne('.my-class')` or `stage.findOne('#my-id')`
7. **Set `Konva.pixelRatio` before creating stages** — global setting, must be set early
8. **Use `dragBoundFunc` for constraints** — cleaner than clamping positions in `dragmove`
9. **Call `layer.draw()` after manual changes** — or use `batchDraw()` for multiple changes
10. **Destroy nodes you don't need** — `node.destroy()` removes from tree and frees memory
