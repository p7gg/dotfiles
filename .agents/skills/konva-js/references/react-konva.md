# react-konva Integration

react-konva provides React components that map to Konva shapes. It renders shapes declaratively using React's reconciliation.

**Install:** `npm install konva react-konva`

---

## Basic Usage

```jsx
import { Stage, Layer, Rect, Circle, Text } from 'react-konva';

function App() {
  return (
    <Stage width={window.innerWidth} height={window.innerHeight}>
      <Layer>
        <Rect
          x={50}
          y={50}
          width={100}
          height={50}
          fill="red"
          stroke="black"
          strokeWidth={2}
          cornerRadius={8}
        />
        <Circle x={200} y={100} radius={40} fill="green" />
        <Text x={50} y={150} text="Hello!" fontSize={24} />
      </Layer>
    </Stage>
  );
}
```

---

## State-Driven Shapes

```jsx
import { useState } from 'react';
import { Stage, Layer, Rect } from 'react-konva';

function DraggableBox() {
  const [pos, setPos] = useState({ x: 100, y: 100 });

  return (
    <Stage width={800} height={600}>
      <Layer>
        <Rect
          x={pos.x}
          y={pos.y}
          width={100}
          height={100}
          fill="blue"
          draggable
          onDragEnd={(e) => {
            setPos({ x: e.target.x(), y: e.target.y() });
          }}
        />
      </Layer>
    </Stage>
  );
}
```

---

## Using Refs to Access Konva Nodes

```jsx
import { useRef, useEffect } from 'react';
import { Stage, Layer, Rect } from 'react-konva';

function AnimatedRect() {
  const rectRef = useRef(null);

  useEffect(() => {
    // Access the underlying Konva node
    const node = rectRef.current;
    node.to({ x: 300, duration: 1 });
  }, []);

  return (
    <Stage width={800} height={600}>
      <Layer>
        <Rect
          ref={rectRef}
          x={50}
          y={50}
          width={100}
          height={100}
          fill="purple"
        />
      </Layer>
    </Stage>
  );
}
```

---

## Events

```jsx
<Rect
  onClick={(e) => console.log('clicked', e.target)}
  onMouseEnter={(e) => e.target.fill('red')}
  onMouseLeave={(e) => e.target.fill('blue')}
  onDragStart={(e) => e.target.opacity(0.5)}
  onDragEnd={(e) => e.target.opacity(1)}
  onTap={(e) => console.log('tapped')}
/>
```

---

## Transformer with React

```jsx
import { useState, useRef, useEffect } from 'react';
import { Stage, Layer, Rect, Transformer } from 'react-konva';

function TransformableRect() {
  const shapeRef = useRef(null);
  const trRef = useRef(null);
  const [isSelected, setIsSelected] = useState(false);

  useEffect(() => {
    if (isSelected && trRef.current && shapeRef.current) {
      trRef.current.nodes([shapeRef.current]);
      trRef.current.getLayer().batchDraw();
    }
  }, [isSelected]);

  return (
    <Stage width={800} height={600} onClick={() => setIsSelected(false)}>
      <Layer>
        <Rect
          ref={shapeRef}
          x={100}
          y={100}
          width={100}
          height={100}
          fill="blue"
          draggable
          onClick={(e) => {
            e.cancelBubble = true;
            setIsSelected(true);
          }}
        />
        {isSelected && (
          <Transformer
            ref={trRef}
            boundBoxFunc={(oldBox, newBox) => {
              // Prevent resizing below minimum size
              if (newBox.width < 20 || newBox.height < 20) {
                return oldBox;
              }
              return newBox;
            }}
          />
        )}
      </Layer>
    </Stage>
  );
}
```

---

## Custom Shape Component

```jsx
import { Shape } from 'react-konva';

function CustomShape({ fill, stroke, strokeWidth }) {
  return (
    <Shape
      sceneFunc={(ctx, shape) => {
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(100, 0);
        ctx.lineTo(50, 100);
        ctx.closePath();
        ctx.fillStrokeShape(shape);
      }}
      fill={fill}
      stroke={stroke}
      strokeWidth={strokeWidth}
    />
  );
}
```

---

## Image Component

```jsx
import { useState } from 'react';
import { useImage } from 'react-konva';
import { Stage, Layer, Image } from 'react-konva';

function MyImage() {
  const image = useImage('/path/to/image.jpg');

  return (
    <Stage width={800} height={600}>
      <Layer>
        <Image image={image} x={50} y={50} width={200} height={150} />
      </Layer>
    </Stage>
  );
}
```

### useImage Hook

```jsx
import { useImage } from 'react-konva';

// Basic usage
const image = useImage(url);

// With crossOrigin
const image = useImage(url, 'anonymous');

// Check if loaded
if (image) {
  // image is ready
}
```

---

## Text Component

```jsx
<Text
  x={50}
  y={50}
  text="Hello World"
  fontSize={24}
  fontFamily="Arial"
  fontStyle="bold"
  fill="black"
  align="center"
  width={200}
  padding={10}
  lineHeight={1.4}
  wrap="word"
  ellipsis
/>
```

---

## Group Component

```jsx
import { Stage, Layer, Group, Rect, Text } from 'react-konva';

function LabeledBox({ x, y, label }) {
  return (
    <Group x={x} y={y} draggable>
      <Rect width={120} height={60} fill="lightblue" cornerRadius={4} />
      <Text
        x={10}
        y={20}
        text={label}
        fontSize={16}
      />
    </Group>
  );
}
```

---

## Rendering Lists of Shapes

```jsx
function ShapeList({ shapes }) {
  return (
    <Layer>
      {shapes.map((shape) => {
        if (shape.type === 'rect') {
          return (
            <Rect
              key={shape.id}
              x={shape.x}
              y={shape.y}
              width={shape.width}
              height={shape.height}
              fill={shape.fill}
            />
          );
        }
        if (shape.type === 'circle') {
          return (
            <Circle
              key={shape.id}
              x={shape.x}
              y={shape.y}
              radius={shape.radius}
              fill={shape.fill}
            />
          );
        }
        return null;
      })}
    </Layer>
  );
}
```

---

## Performance Tips for react-konva

1. **Use `key` properly** — always use stable, unique keys for shape lists
2. **Minimize re-renders** — use `React.memo` for shape components
3. **Batch state updates** — use `useReducer` or batch multiple changes
4. **Use refs for animations** — avoid triggering React re-renders for every frame
5. **Separate layers** — put static content in one layer, interactive in another
6. **Use `batchDraw()`** — call `layer.batchDraw()` via ref instead of forcing React updates

```jsx
// Bad: re-rendering on every animation frame
function BadAnimation() {
  const [x, setX] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setX(x => x + 1), 16);
    return () => clearInterval(id);
  }, []);
  return <Rect x={x} ... />; // re-renders every frame
}

// Good: use Konva animation via ref
function GoodAnimation() {
  const rectRef = useRef(null);
  useEffect(() => {
    const anim = new Konva.Animation((frame) => {
      const dist = 50 * (frame.timeDiff / 1000);
      rectRef.current.move({ x: dist, y: 0 });
    }, rectRef.current.getLayer());
    anim.start();
    return () => anim.stop();
  }, []);
  return <Rect ref={rectRef} ... />; // no re-renders
}
```

---

## Portal (Rendering Outside Normal Hierarchy)

```jsx
import { Portal } from 'react-konva';

function Tooltip({ x, y, text }) {
  return (
    <Portal>
      <Group x={x} y={y}>
        <Text text={text} fill="white" />
      </Group>
    </Portal>
  );
}
```

---

## Suspense with useImage

```jsx
import { Suspense } from 'react';
import { useImage } from 'react-konva';

function ImageWithSuspense({ url }) {
  // useImage works with React Suspense
  const image = useImage(url);
  return <Image image={image} />;
}

function App() {
  return (
    <Suspense fallback={<Text text="Loading..." />}>
      <ImageWithSuspense url="/image.jpg" />
    </Suspense>
  );
}
```
