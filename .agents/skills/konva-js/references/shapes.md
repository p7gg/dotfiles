# Konva.js Shapes Reference

All shapes extend `Konva.Shape` and inherit common properties: `x`, `y`, `width`, `height`, `rotation`, `scaleX`, `scaleY`, `opacity`, `visible`, `draggable`, `name`, `id`, `listening`, `offsetX`, `offsetY`, plus all fill/stroke/shadow styling options.

---

## Konva.Rect

Rectangle with optional rounded corners.

```js
const rect = new Konva.Rect({
  x: 50,
  y: 50,
  width: 100,
  height: 60,
  fill: 'red',
  stroke: 'black',
  strokeWidth: 2,
  cornerRadius: 8,    // rounded corners (single value or [topLeft, topRight, bottomRight, bottomLeft])
  draggable: true,
});
```

**Unique properties:**
- `cornerRadius: Number | Number[]` — radius of corners. Single value for all corners, or array of 4 values.

---

## Konva.Circle

Circle defined by center point and radius.

```js
const circle = new Konva.Circle({
  x: 100,
  y: 100,
  radius: 50,
  fill: 'green',
  stroke: 'black',
  strokeWidth: 3,
  draggable: true,
});
```

**Unique properties:**
- `radius: Number` — **required**. Radius of the circle.

---

## Konva.Ellipse

Ellipse defined by center point and x/y radii.

```js
const ellipse = new Konva.Ellipse({
  x: 150,
  y: 100,
  radius: { x: 80, y: 40 },
  fill: 'blue',
  stroke: 'black',
  strokeWidth: 2,
});
```

**Unique properties:**
- `radius: { x: Number, y: Number }` — **required**. Radii for x and y axes.
- `radiusX: Number` — get/set x radius independently.
- `radiusY: Number` — get/set y radius independently.

---

## Konva.Line

Polyline, spline, or closed polygon defined by an array of points.

```js
// Simple line
const line = new Konva.Line({
  points: [10, 10, 100, 50, 200, 30],
  stroke: 'red',
  strokeWidth: 3,
  lineCap: 'round',
  lineJoin: 'round',
});

// Smooth curve (spline)
const curve = new Konva.Line({
  points: [10, 10, 100, 50, 200, 30, 300, 80],
  stroke: 'blue',
  strokeWidth: 3,
  tension: 0.5,  // 0 = straight lines, higher = curvier
});

// Closed polygon (filled)
const polygon = new Konva.Line({
  points: [50, 10, 90, 90, 10, 50],
  fill: 'yellow',
  stroke: 'black',
  strokeWidth: 2,
  closed: true,
});

// Bezier curve
const bezier = new Konva.Line({
  points: [10, 50, 50, 10, 150, 90, 190, 50],
  stroke: 'purple',
  strokeWidth: 3,
  bezier: true,  // interpret points as bezier control points
});
```

**Unique properties:**
- `points: Number[]` — **required**. Flat array `[x1, y1, x2, y2, ...]`.
- `tension: Number` — curve smoothness. 0 = straight, 1+ = very curvy.
- `closed: Boolean` — if true, closes the path and allows fill.
- `bezier: Boolean` — if true, interprets points as bezier control points.

---

## Konva.Arrow

Line with arrowhead(s).

```js
const arrow = new Konva.Arrow({
  points: [50, 50, 200, 100],
  stroke: 'red',
  strokeWidth: 3,
  fill: 'red',  // arrowhead fill color
  pointerLength: 15,
  pointerWidth: 12,
  pointerAtBeginning: false,  // arrow at start
  pointerAtEnding: true,      // arrow at end (default)
});
```

**Unique properties:**
- `points: Number[]` — **required**. Same format as Line.
- `pointerLength: Number` — length of arrowhead (default: 10).
- `pointerWidth: Number` — width of arrowhead (default: 10).
- `pointerAtBeginning: Boolean` — draw arrow at start point (default: false).
- `pointerAtEnding: Boolean` — draw arrow at end point (default: true).
- `tension`, `closed`, `bezier` — inherited from Line.

---

## Konva.Text

Multi-line text with rich formatting.

```js
const text = new Konva.Text({
  x: 20,
  y: 20,
  text: 'Hello World!\nSecond line',
  fontSize: 24,
  fontFamily: 'Arial',
  fontStyle: 'bold italic',  // 'normal', 'bold', 'italic', 'bold italic'
  fontVariant: 'normal',     // 'normal', 'small-caps'
  fill: 'black',
  align: 'center',           // 'left', 'center', 'right', 'justify'
  verticalAlign: 'middle',   // 'top', 'middle', 'bottom'
  padding: 10,
  lineHeight: 1.4,
  wrap: 'word',              // 'word', 'char', 'none'
  ellipsis: true,            // add "..." when text overflows
  width: 200,
  height: 100,
  letterSpacing: 2,
  textDecoration: 'underline', // 'underline', 'line-through', or combination
});
```

**Unique properties:**
- `text: String` — **required**. Text content. Use `\n` for line breaks.
- `fontFamily: String` — CSS font family (default: 'Arial').
- `fontSize: Number` — font size in pixels (default: 12).
- `fontStyle: String` — 'normal', 'bold', 'italic', 'bold italic'.
- `fontVariant: String` — 'normal', 'small-caps'.
- `align: String` — horizontal alignment.
- `verticalAlign: String` — vertical alignment.
- `padding: Number` — inner padding.
- `lineHeight: Number` — line height multiplier (default: 1).
- `wrap: String` — word wrapping mode.
- `ellipsis: Boolean` — add ellipsis on overflow.
- `width`, `height: Number` — text box dimensions.
- `letterSpacing: Number` — letter spacing in pixels.
- `textDecoration: String` — 'underline', 'line-through'.
- `direction: String` — text direction ('ltr', 'rtl', 'inherit').

**Methods:**
- `getTextWidth()` — returns text width without padding.
- `measureSize(text)` — measures a string with the current font settings.

---

## Konva.TextPath

Text rendered along an SVG path.

```js
const textPath = new Konva.TextPath({
  x: 50,
  y: 50,
  text: 'Text along a curved path',
  fontSize: 20,
  fontFamily: 'Arial',
  fill: '#333',
  data: 'M10,50 Q50,0 90,50 T170,50',  // SVG path
  textBaseline: 'middle',  // 'top', 'bottom', 'middle', 'alphabetic', 'hanging'
  letterSpacing: 1,
  kerningFunc: (leftChar, rightChar) => {
    // custom kerning
    return 0;
  },
});
```

**Unique properties:**
- `text: String` — **required**.
- `data: String` — **required**. SVG path data.
- `fontFamily`, `fontSize`, `fontStyle`, `fontVariant` — same as Text.
- `textBaseline: String` — vertical alignment relative to path.
- `letterSpacing: Number` — spacing between characters.
- `kerningFunc: Function` — `(leftChar, rightChar) => number` for custom kerning.
- `align: String` — 'left', 'center', 'right'.

---

## Konva.Image

Raster image (HTMLImageElement, HTMLCanvasElement, or HTMLVideoElement).

```js
const imageObj = new Image();
imageObj.onload = () => {
  const image = new Konva.Image({
    x: 50,
    y: 50,
    image: imageObj,
    width: 200,
    height: 150,
    crop: { x: 10, y: 10, width: 100, height: 80 },  // crop source image
    cornerRadius: 8,
    draggable: true,
  });
  layer.add(image);
  layer.draw();
};
imageObj.src = '/path/to/image.jpg';

// Or load from URL directly
Konva.Image.fromURL('/path/to/image.jpg', (img) => {
  const konvaImage = new Konva.Image({
    x: 50, y: 50, image: img,
    width: 200, height: 150,
  });
  layer.add(konvaImage);
  layer.draw();
}, (error) => {
  console.error('Failed to load image', error);
});
```

**Unique properties:**
- `image: HTMLImageElement | HTMLCanvasElement | HTMLVideoElement` — **required**.
- `crop: { x, y, width, height }` — crop region of source image.
- `cropX`, `cropY`, `cropWidth`, `cropHeight` — individual crop properties.
- `cornerRadius: Number` — rounded corners on the image.

**Static methods:**
- `Konva.Image.fromURL(url, onLoad, onError)` — load image from URL.

---

## Konva.Path

Shape defined by SVG path data.

```js
const path = new Konva.Path({
  x: 50,
  y: 50,
  data: 'M0,0 L100,0 L100,100 L0,100 Z',  // SVG path
  fill: 'blue',
  stroke: 'black',
  strokeWidth: 2,
  scaleX: 2,
  scaleY: 2,
});
```

**Unique properties:**
- `data: String` — **required**. SVG path data string.

**Supported SVG commands:** M, m, L, l, H, h, V, v, Q, q, T, t, C, c, S, s, A, a, Z, z

**Methods:**
- `getLength()` — returns total length of the path.
- `getPointAtLength(length)` — returns `{ x, y }` at a specific distance along the path.

---

## Konva.Star

Star polygon with configurable points.

```js
const star = new Konva.Star({
  x: 100,
  y: 100,
  numPoints: 5,
  innerRadius: 30,
  outerRadius: 60,
  fill: 'gold',
  stroke: 'orange',
  strokeWidth: 2,
  rotation: 18,  // rotate to point upward
});
```

**Unique properties:**
- `numPoints: Number` — **required**. Number of points.
- `innerRadius: Number` — **required**. Radius of inner vertices.
- `outerRadius: Number` — **required**. Radius of outer vertices.

---

## Konva.RegularPolygon

Regular polygon (triangle, pentagon, hexagon, etc.).

```js
const hexagon = new Konva.RegularPolygon({
  x: 100,
  y: 100,
  sides: 6,
  radius: 50,
  fill: 'teal',
  stroke: 'black',
  strokeWidth: 2,
  cornerRadius: 4,  // optional rounded corners
});
```

**Unique properties:**
- `sides: Number` — **required**. Number of sides.
- `radius: Number` — **required**. Distance from center to vertices.
- `cornerRadius: Number` — optional rounded corners.

---

## Konva.Ring

Annulus (donut shape).

```js
const ring = new Konva.Ring({
  x: 100,
  y: 100,
  innerRadius: 30,
  outerRadius: 60,
  fill: 'purple',
  stroke: 'black',
  strokeWidth: 2,
});
```

**Unique properties:**
- `innerRadius: Number` — **required**.
- `outerRadius: Number` — **required**.

---

## Konva.Arc

Arc segment (partial ring).

```js
const arc = new Konva.Arc({
  x: 100,
  y: 100,
  innerRadius: 30,
  outerRadius: 60,
  angle: 90,          // degrees
  rotation: -45,      // starting angle
  clockwise: true,
  fill: 'orange',
  stroke: 'black',
  strokeWidth: 2,
});
```

**Unique properties:**
- `innerRadius: Number` — **required**.
- `outerRadius: Number` — **required**.
- `angle: Number` — **required**. Arc angle in degrees.
- `clockwise: Boolean` — draw direction (default: false).

---

## Konva.Wedge

Pie slice shape.

```js
const wedge = new Konva.Wedge({
  x: 100,
  y: 100,
  radius: 60,
  angle: 60,           // degrees
  rotation: -120,      // orientation
  clockwise: true,
  fill: 'red',
  stroke: 'black',
  strokeWidth: 2,
});
```

**Unique properties:**
- `radius: Number` — **required**.
- `angle: Number` — **required**. Wedge angle in degrees.
- `clockwise: Boolean` — draw direction.

---

## Konva.Label

Container for Text + Tag (speech bubble / tooltip).

```js
const label = new Konva.Label({
  x: 100,
  y: 100,
  opacity: 0.9,
});

label.add(new Konva.Tag({
  fill: '#bbb',
  stroke: '#333',
  strokeWidth: 1,
  pointerDirection: 'up',    // 'up', 'down', 'left', 'right', 'none'
  pointerWidth: 20,
  pointerHeight: 15,
  cornerRadius: 5,
}));

label.add(new Konva.Text({
  text: 'Hello!',
  fontSize: 18,
  padding: 10,
  fill: 'black',
}));

layer.add(label);
```

**Methods:**
- `getText()` — returns the Text child shape.
- `getTag()` — returns the Tag child shape.

---

## Konva.Tag

Pointer background for labels.

```js
const tag = new Konva.Tag({
  fill: 'lightgray',
  stroke: 'gray',
  strokeWidth: 1,
  pointerDirection: 'down',  // 'up', 'down', 'left', 'right', 'none'
  pointerWidth: 16,
  pointerHeight: 12,
  cornerRadius: 4,
});
```

**Unique properties:**
- `pointerDirection: String` — direction of pointer arrow.
- `pointerWidth: Number` — width of pointer.
- `pointerHeight: Number` — height of pointer.
- `cornerRadius: Number` — rounded corners.

---

## Konva.Sprite

Sprite sheet animation.

```js
const sprite = new Konva.Sprite({
  x: 100,
  y: 100,
  image: imageObj,  // sprite sheet image
  animation: 'walk',
  animations: {
    walk: [
      // x, y, width, height for each frame
      0, 0, 64, 64,
      64, 0, 64, 64,
      128, 0, 64, 64,
      192, 0, 64, 64,
    ],
    jump: [
      0, 64, 64, 64,
      64, 64, 64, 64,
    ],
  },
  frameRate: 12,       // frames per second
  frameIndex: 0,
});

sprite.start();   // start animation
sprite.stop();    // stop animation
sprite.isRunning(); // check if running
sprite.animation('jump'); // switch animation
```

**Unique properties:**
- `image: HTMLImageElement` — **required**. Sprite sheet.
- `animations: Object` — **required**. Map of animation name to frame data array.
- `animation: String` — current animation key.
- `frameRate: Number` — frames per second (default: 17).
- `frameIndex: Number` — current frame index.
- `offsets: Object` — map of animation name to offset values.

**Methods:**
- `start()` — start animation.
- `stop()` — stop animation.
- `isRunning()` — returns boolean.

---

## Konva.Shape (Custom)

Custom drawn shape using canvas context.

```js
const customShape = new Konva.Shape({
  x: 50,
  y: 50,
  fill: 'red',
  stroke: 'black',
  strokeWidth: 2,
  sceneFunc(ctx, shape) {
    // Draw on the scene canvas
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(100, 0);
    ctx.lineTo(100, 80);
    ctx.lineTo(0, 80);
    ctx.closePath();
    // Fill and stroke using shape's fill/stroke properties
    ctx.fillStrokeShape(shape);
  },
  hitFunc(ctx, shape) {
    // Optional: custom hit area (larger or different from visual)
    ctx.beginPath();
    ctx.arc(50, 40, 60, 0, Math.PI * 2);
    ctx.fillStrokeShape(shape);
  },
});
```

**Unique properties:**
- `sceneFunc: Function` — `(context, shape) => void`. Draw function for the visible canvas.
- `hitFunc: Function` — `(context, shape) => void`. Draw function for the hit detection canvas.

**Methods:**
- `hasShadow()` — returns whether shadow will be rendered.
- `hasFill()` — returns whether fill will be rendered.
- `hasStroke()` — returns whether stroke will be rendered.
- `intersects(point)` — checks if point is inside this shape.
- `getSelfRect()` — returns `{ x, y, width, height }` without transforms.
- `drawHitFromCache(alphaThreshold)` — generate hit region from cached scene.

---

## Fill Priority

When multiple fill types are set, use `fillPriority` to choose which one renders:

```js
shape.fillPriority('color');           // use solid color (default)
shape.fillPriority('pattern');         // use pattern fill
shape.fillPriority('linear-gradient'); // use linear gradient
shape.fillPriority('radial-gradient'); // use radial gradient
```
