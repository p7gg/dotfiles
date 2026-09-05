# Konva.js Node API Reference

All nodes (Stage, Layer, Group, Shape) extend `Konva.Node`. This document covers the common API available on every node.

---

## Position & Transforms

```js
// Position (relative to parent)
node.x(100);
node.y(200);
node.position({ x: 100, y: 200 });

// Absolute position (relative to stage origin)
const absPos = node.getAbsolutePosition();
node.absolutePosition({ x: 300, y: 400 });

// Rotation (degrees)
node.rotation(45);

// Scale
node.scaleX(2);
node.scaleY(1.5);
node.scale({ x: 2, y: 1.5 });

// Skew
node.skewX(0.1);
node.skewY(0.1);
node.skew({ x: 0.1, y: 0.1 });

// Offset (rotation/scale center)
node.offsetX(50);
node.offsetY(50);
node.offset({ x: 50, y: 50 });

// Size
node.width(200);
node.height(100);
node.size({ width: 200, height: 100 });

// Get transforms
node.getTransform();              // local transform
node.getAbsoluteTransform();      // including ancestors
node.getAbsoluteScale();          // including ancestor scales
node.getAbsoluteRotation();       // including ancestor rotations
```

### Moving Relative to Current Position

```js
node.move({ x: 10, y: -5 });  // shift by offset
node.rotate(15);               // add to current rotation
```

---

## Visibility & Listening

```js
// Visibility
node.visible(false);
node.hide();
node.show();
node.isVisible();  // true only if node AND all ancestors are visible

// Event listening
node.listening(false);
node.isListening();  // true only if node AND all ancestors are listening
```

**Important:** `listening(false)` disables the hit graph for this node and all descendants. Use this instead of the deprecated `disableHitGraph()`.

---

## Opacity

```js
node.opacity(0.5);  // 0 = transparent, 1 = opaque
node.getAbsoluteOpacity();  // including ancestor opacity
```

---

## Drag and Drop

```js
node.draggable(true);
node.dragDistance(5);  // minimum pixels before drag starts

// Constrain dragging
node.dragBoundFunc(function(pos) {
  return {
    x: Math.max(0, Math.min(pos.x, 1000)),
    y: this.y(),  // lock Y axis
  };
});

// Programmatic control
node.startDrag();
node.stopDrag();
node.isDragging();
```

---

## Z-Index & Layering

```js
node.zIndex();        // get index among siblings
node.zIndex(3);       // set index
node.moveToTop();     // highest among siblings
node.moveToBottom();  // lowest
node.moveUp();        // one level up
node.moveDown();      // one level down
```

---

## Node Tree Navigation

```js
// Up the tree
node.getParent();
node.getLayer();
node.getStage();
node.getAncestors();  // [parent, grandparent, ...]

// Down the tree (for Container nodes)
container.getChildren();
container.getChildren((child) => child.name() === 'foo');  // with filter

// Find by selector
stage.findOne('#myId');       // by id
stage.findOne('.myClass');    // by name
stage.findOne('Rect');        // by class name
stage.findOne('Rect.myClass');// combined
stage.find('.highlighted');   // all matching
stage.find('Group > Rect');   // direct children

// Find with function
stage.findOne((node) => node.x() > 100);

// Ancestor queries
node.findAncestor('.group');
node.findAncestor((n) => n.name() === 'myGroup');

// Check relationships
container.isAncestorOf(child);
```

---

## Events

```js
// Bind events
node.on('click', handler);
node.on('mouseenter mouseleave', handler);
node.on('dragstart', handler);
node.on('click.myNamespace', handler);  // namespaced

// Remove events
node.off('click');
node.off('.myNamespace');  // all in namespace
node.off();                // all events

// Fire custom events
node.fire('myCustomEvent', { detail: 'data' });
node.fire('click', {}, true);  // with bubbling

// Common events:
// mouseover, mousemove, mouseout, mouseenter, mouseleave
// mousedown, mouseup, wheel, contextmenu
// click, dblclick
// touchstart, touchmove, touchend, tap, dbltap
// dragstart, dragmove, dragend
```

---

## Name & ID

```js
node.id('uniqueId');    // global unique identifier
node.name('myShape');   // non-unique, can have multiple
node.name();            // get current name

// Add/remove names (a node can have multiple names)
node.addName('selected');
node.addName('highlighted');
node.hasName('selected');
node.removeName('selected');
```

---

## Cloning & Serialization

```js
// Clone
const clone = node.clone();
const clone = node.clone({ x: 200, fill: 'blue' });  // override props

// Serialize
const obj = node.toObject();     // JS object
const json = node.toJSON();      // JSON string

// Deserialize
const restored = Konva.Node.create(json, 'containerId');
const restored = Konva.Node.create(obj, containerElement);
```

**Note:** Serialization does NOT preserve:
- Custom `sceneFunc` / `hitFunc`
- Event handlers
- Image sources (only the reference, not the data)

After deserializing, you must re-attach these manually.

---

## Export

```js
// To data URL (base64)
const dataURL = node.toDataURL({
  mimeType: 'image/png',    // or 'image/jpeg'
  quality: 0.9,             // for JPEG (0-1)
  pixelRatio: 2,            // retina
  x: 0, y: 0,               // crop region
  width: 500, height: 400,
  imageSmoothingEnabled: true,
});

// To Blob
node.toBlob((blob) => {
  // upload or save blob
}, { pixelRatio: 2 });

// To Image (HTMLImageElement)
node.toImage((img) => {
  document.body.appendChild(img);
}, { pixelRatio: 2 });

// To Canvas element
node.toCanvas({ pixelRatio: 2 }, (canvas) => {
  // canvas is an HTMLCanvasElement
});
```

---

## Caching

```js
// Cache a node (creates offscreen canvas)
node.cache({
  x: 0, y: 0,             // bounding box
  width: 100, height: 100,
  pixelRatio: 2,
  drawBorder: false,      // debug: show cache bounds
  imageSmoothingEnabled: true,
});

node.clearCache();
node.isCached();
```

**When to cache:**
- Applying filters
- Complex shapes drawn repeatedly
- Shapes with shadows + opacity
- Hit detection from visual (drawHitFromCache)

---

## Drawing

```js
node.draw();              // draw scene + hit graphs
layer.draw();             // redraw a layer
stage.draw();             // redraw all layers
layer.batchDraw();        // schedule draw for next frame
```

---

## Client Rect

```js
// Get bounding box including transforms, stroke, shadow
const rect = node.getClientRect();
// { x, y, width, height }

// Options
const rect = node.getClientRect({
  skipTransform: false,
  skipShadow: false,
  skipStroke: false,
  relativeTo: stage,  // or any ancestor
});

// Check if on screen
node.isClientRectOnScreen({ x: 10, y: 10 });  // margin
```

---

## Destroy & Remove

```js
node.remove();    // remove from parent (can be re-added)
node.destroy();   // permanently remove and clean up (also destroys children)
```

---

## Tween Shortcut

```js
// Animate any property
node.to({
  x: 200,
  rotation: 360,
  opacity: 0,
  duration: 1,
  easing: Konva.Easings.EaseInOut,
  onFinish: () => {},
});
```

---

## Global Properties (Konva namespace)

```js
// Device pixel ratio (set BEFORE creating stages)
Konva.pixelRatio = 2;

// Auto-draw (default: true)
Konva.autoDrawEnabled = true;

// Drag distance (default: 3px)
Konva.dragDistance = 5;

// Drag buttons (default: [0, 1] = left + middle)
Konva.dragButtons = [0];  // left only

// Show warnings (default: true)
Konva.showWarnings = false;

// Angle unit (default: degrees)
Konva.angleDeg = false;  // use radians

// Hit detection during drag (default: false, for performance)
Konva.hitOnDragEnabled = true;

// Release canvas on destroy (default: true, Safari memory fix)
Konva.releaseCanvasOnDestroy = true;

// Check drag state
Konva.isDragging();   // any drag in progress
```

---

## Hit Detection

```js
// Get shape at point
const shape = stage.getIntersection({ x: 100, y: 200 });

// Get all shapes at point (on a container, slower)
const shapes = group.getAllIntersections({ x: 100, y: 200 });

// Check if point is in shape (regardless of overlap)
shape.intersects({ x: 50, y: 50 });

// Get pointer position relative to a node
const pos = node.getRelativePointerPosition();
```

### Custom Hit Area

```js
shape.hitFunc((ctx) => {
  // Draw a larger hit area for easier clicking
  ctx.beginPath();
  ctx.arc(0, 0, 60, 0, Math.PI * 2);  // bigger than visual
  ctx.fillStrokeShape(shape);
});
```

### Hit from Cache

```js
// Generate hit region from the cached visual
shape.cache();
shape.drawHitFromCache(50);  // alpha threshold (0-255)
```

---

## Prevent Default

```js
// By default, shapes prevent default on pointer events
// (prevents native scrolling during drag)
shape.preventDefault(false);  // allow default actions
```

---

## Transforms Enabled

```js
// Control which transforms apply
node.transformsEnabled('all');      // all transforms (default)
node.transformsEnabled('position');  // only x/y, ignore rotation/scale
node.transformsEnabled('none');      // no transforms
```

---

## Global Composite Operation

```js
node.globalCompositeOperation('source-over');   // default
node.globalCompositeOperation('multiply');
node.globalCompositeOperation('screen');
node.globalCompositeOperation('overlay');
node.globalCompositeOperation('destination-in');
// Note: doesn't affect hit graph
```

---

## Utility Methods

```js
node.getClassName();  // 'Rect', 'Circle', 'Group', etc.
node.getType();       // 'Shape', 'Container', 'Stage', 'Layer'
node.getDepth();      // depth in tree (Stage=0, Layer=1, etc.)
node.getAbsoluteZIndex();  // absolute z-index across all layers
```
