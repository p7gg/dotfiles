# Filters

Konva includes many image filters that operate on `Konva.Image` nodes. Filters can be applied as functions (pixel manipulation) or as CSS-like filters when supported.

## Applying Filters

```js
image.filters([Konva.Filters.Blur, Konva.Filters.Brighten]);
image.blurRadius(8);
image.brightness(0.2);
image.cache(); // Required after setting filters
```

Set filter parameters on the node itself (e.g., `image.brightness(0.2)`) then call `image.cache()` to re-render the cached image with filters applied.

## Available Filters

- Blur (use `blurRadius`)
- Brighten (use `brightness`)
- Brightness (CSS-compatible brightness)
- Contrast (use `contrast`)
- Emboss (use `embossStrength`, `embossWhiteLevel`, `embossDirection`, `embossBlend`)
- Enhance (use `enhance`)
- Grayscale
- HSL (use `hue`, `saturation`, `luminance`)
- HSV (use `hue`, `saturation`, `value`)
- Invert
- Mask
- Noise (use `noise` 0..1)
- Pixelate (use `pixelSize`)
- Posterize (use `levels` 0..1)
- RGB / RGBA
- Sepia
- Solarize
- Threshold (0..1)

## Example: Blur + Brightness

```js
const image = new Konva.Image({ image: imageObj });
image.filters([Konva.Filters.Blur, Konva.Filters.Brighten]);
image.blurRadius(5);
image.brightness(0.1);
image.cache();
layer.add(image);
layer.draw();
```

## Performance

- Filters require offscreen rendering (cache) and can be expensive on large images.
- Use lower `pixelRatio` or crop the image when applying expensive filters.
- Reuse cached results when possible.
