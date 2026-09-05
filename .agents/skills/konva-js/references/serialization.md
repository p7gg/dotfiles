# Serialization & Export

Konva supports serializing stages and nodes to JSON, and exporting to images or blobs.

## toJSON / fromJSON

```js
// Serialize entire stage
const json = stage.toJSON();

// Later: create a new stage from JSON
const restoredStage = Konva.Node.create(json, 'container');
```

Notes:
- JSON serialization captures node attributes and structure but not runtime-specific items: custom `sceneFunc`/`hitFunc`, event handlers, or in-memory image pixel data.
- After deserialization, you must reattach images, event listeners, and custom drawing functions.

## toDataURL / toBlob / toImage

```js
// Data URL
const dataURL = stage.toDataURL({ mimeType: 'image/png', pixelRatio: 2 });

// Blob (async)
stage.toBlob((blob) => {
  // upload blob
}, { pixelRatio: 2 });

// HTMLImageElement (async)
stage.toImage({ pixelRatio: 2 }, (img) => {
  document.body.appendChild(img);
});
```

Options common to export methods:
- `mimeType` — e.g., `image/png` or `image/jpeg`
- `quality` — for `image/jpeg` (0..1)
- `x, y, width, height` — crop rectangle
- `pixelRatio` — control resolution

## Exporting Individual Layers or Nodes

```js
// Convert single layer to dataURL
const url = layer.toDataURL({ pixelRatio: 2 });

// Convert node to canvas
node.toCanvas({ pixelRatio: 2 }, (canvas) => {
  document.body.appendChild(canvas);
});
```

## Best Practices

- Use `pixelRatio` to produce high-resolution exports (retina). Set higher only for export, not for real-time rendering.
- For large exported images, stream to `toBlob` to avoid memory spikes.
- Re-cache shapes before exporting if they use filters.
