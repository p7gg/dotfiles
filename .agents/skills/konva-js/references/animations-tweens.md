# Animations & Tweens

Konva provides two primary animation systems:

- Frame-based animations using `Konva.Animation` — you get a callback every frame with timing information.
- Property-based tweens using `Konva.Tween` (and the shorthand `node.to()`) — smooth interpolation of node properties over time.

## Konva.Animation

Use `Konva.Animation` for manual per-frame updates (physics, custom motion, procedural animation).

```js
// Move a node right at 50 pixels/second
const anim = new Konva.Animation((frame) => {
  // frame.timeDiff = ms since last frame
  const dx = 50 * (frame.timeDiff / 1000);
  node.move({ x: dx });
}, layer);

anim.start();
// anim.stop();
```

Frame object fields: `time` (ms since animation start), `timeDiff` (ms since last frame), `frameRate` (estimated FPS).

Use `anim.setLayers([layer1, layer2])` to control which layers Konva redraws for this animation.

## Konva.Tween

Tweens interpolate numeric and color properties on a node over a fixed duration with easing.

```js
const tween = new Konva.Tween({
  node: shape,
  duration: 0.6, // seconds
  easing: Konva.Easings.EaseInOut,
  x: 300,
  rotation: 180,
  fill: 'red',
  onFinish: () => console.log('done'),
});

tween.play();
// tween.pause(); tween.reverse(); tween.reset(); tween.finish();
```

Shorthand: `node.to({ x: 100, duration: 0.4, easing: Konva.Easings.Linear })` — convenient one-off tween.

## Easings

Konva exposes common easing functions in `Konva.Easings` (Linear, EaseIn, EaseOut, BackEaseInOut, Elastic, Bounce, etc.). Use them to control motion curves.

## Tips

- Prefer `Konva.Animation` for continuous or physics-driven updates where you control every frame.
- Prefer Tweens for declarative transitions of node properties.
- Avoid combining many independent tweens that target the same node at the same time — coordinate them or cancel previous tweens.
- Use `layer.batchDraw()` inside animation callbacks to avoid forcing synchronous draws.
- Stop animations on component unmount / cleanup to prevent memory leaks.
