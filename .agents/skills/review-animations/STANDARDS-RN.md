# React Native / Expo Animation Standards

Derived from the `animate-expo` skill; this file is a local addition, not part of upstream emilkowalski/skills.

The checklist for reviewing React Native and Expo motion. Each item is a checkable rule: flag the first form, expect the second. Cite these in findings instead of approximating. Feel is judged on a release build on the slowest supported device; nothing else counts as verified.

## Should it animate? (frequency)

- Flag animation on 100+/day actions (tab switches, keyboard open/close, scrolling, settings toggles); expect the platform default or nothing.
- Flag press feedback or list-navigation motion over 150ms (tens/day tier); expect under 150ms, or nothing.
- Flag a tab switch that slides; expect `animation: 'none'`. Tabs are peers, so sliding implies depth that isn't there.
- Flag motion with no nameable purpose (feedback, spatial consistency, state indication, preventing a jarring change, explanation, delight). Delight belongs only to the rare/first-time tier.
- Flag an `entering` animation on content the user scrolls past all day; expect it already there. Entrances are for content the user asked for and is waiting on.

## Threads (UI runtime vs JS runtime)

- Flag `setState` inside a gesture or scroll handler; expect shared value + `useAnimatedStyle` so React never re-renders per frame. (`setState` on press-in/out is fine: twice per press, not per frame.)
- Flag `scheduleOnRN` (or deprecated `runOnJS`) inside `onUpdate` or a scroll handler; expect it in `onEnd`, or a `useAnimatedReaction` that fires when a value crosses a threshold.
- Flag `runOnJS`; expect `scheduleOnRN(fn, ...args)` from `react-native-worklets` (Reanimated 4).
- Flag a shared value read or written during render (`translateY.get()` in JSX); expect `.get()` / `.set()` only in worklets, handlers and effects.
- Flag `.value` access; expect `.get()` / `.set()` (compiler-safe). Functional update: `sv.set((v) => v + 1)`.
- Flag a function called from a worklet without `'worklet'` as its first line; it throws on device while working in the debugger.
- Flag `PanResponder`; expect `Gesture.Pan()` from gesture-handler.
- Flag core `Animated` for anything a finger touches or scroll drives; expect Reanimated. Core `Animated` can't be gesture-driven without crossing the bridge, and `useNativeDriver` only allows transform and opacity.

## Pick the cheapest tool

- Flag a shared value + worklet for a two-state toggle or press scale; expect a Reanimated CSS transition (`transitionProperty` in the style).
- Flag a hand-rolled loop or mount animation; expect Reanimated CSS animation (`animationName` keyframes).
- Flag manual mount/unmount or list-reflow animation; expect `entering` / `exiting` / `itemLayoutAnimation`.
- Flag a screen transition rebuilt in JS; expect native stack options in Expo Router.
- Flag a hand-built bottom sheet that is its own destination; expect `presentation: 'formSheet'`.
- Flag a rebuilt tab bar, context menu, collapsing large title, or pull-to-refresh; expect `NativeTabs`, `Link.Menu` / `Link.Preview`, `headerLargeTitleEnabled`, `RefreshControl` (hand-roll refresh only as a signature interaction).
- Flag keyboard-following UI built from `Keyboard.addListener` + a timing animation; expect `react-native-keyboard-controller` (`useReanimatedKeyboardAnimation`, with `KeyboardProvider` at the root). The keyboard rides a private system curve, so any fixed duration lags or leads it.
- Flag Lottie used for UI state; expect Lottie for illustration/celebration/empty state only.

## Properties

- Flag animated `width`, `height`, `margin`, `padding`, `flex`, `top`, `left`, `gap`; expect `transform` + `opacity`. These re-run Yoga every frame for the node and its siblings.
- Exception: an absolutely positioned element with no children (tab pill, progress fill) may animate `width`; it keeps the corner radius that `scaleX` would smear.
- Flag a collapsing header that animates `height`; expect a fixed-height container, translated content, `overflow: 'hidden'`.
- Flag `scale(0)`; expect `scale(0.9-0.97)` + `opacity: 0`.
- Flag a `transform` array with scale before translate unintentionally; order matters, keep translate first (`[{ translateY }, { scale }]`).
- Flag animated Android `elevation`; expect opacity of a pre-shadowed layer.
- Flag animated `BlurView` intensity; expect a crossfade of a static `BlurView`'s opacity.
- Prefer `translateY('100%')` over hardcoded px for sheets; percentages are relative to the element's own size.
- Flag an animation to a hardcoded height (text scales with `allowFontScaling`); expect `onLayout` measurement, or a transform.
- Flag `interpolate` on scroll without `Extrapolation.CLAMP`; the value runs past its range (header reappears inverted).

## Spring vs timing

- Flag a timing curve on anything a finger touched; expect a spring (springs carry velocity through interruption, timing restarts).
- Flag mass/stiffness/damping; expect the duration + `dampingRatio` form.

| Interaction | Config |
| --- | --- |
| Default settle, no overshoot | `{ duration: 400, dampingRatio: 1 }` |
| Reposition / snap back after a drag | `{ duration: 400, dampingRatio: 0.8, velocity }` |
| Sheet, drawer | `{ duration: 300, dampingRatio: 0.8, velocity }` |
| Must not pass a hard edge | add `overshootClamping: true` |

- Flag bounce on an element that arrived without momentum (a menu that faded in); expect bounce only when the gesture carried momentum.
- Flag `Easing.in(...)` or any ease-in on UI; expect ease-out. Reanimated's built-in easings are weak, so expect:

```js
const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);      // entering/exiting, default
const EASE_IN_OUT = Easing.bezier(0.77, 0, 0.175, 1);  // moving/morphing on screen
const EASE_SHEET = Easing.bezier(0.32, 0.72, 0, 1);    // iOS sheet curve
```

- Constant motion (progress, marquee) is `linear`.

| Element | Duration |
| --- | --- |
| Press feedback | 100-150ms |
| Toggle, chip, small state change | 150-200ms |
| Sheet, modal, drawer | spring, ~300ms perceived |
| Screen transition | platform default, don't override |

- Flag UI motion over 300ms with no reason. Only platform navigation (iOS push is 350ms) is longer; match the platform there, beat it everywhere else.

## Gestures: handoff, velocity, interruptibility

- Flag a Pan `onStart` that doesn't capture the current value (`context.set(translateY.get())`); grabbing mid-animation teleports. The animation must continue from where the eye last saw it.
- Flag a spring release that doesn't pass `velocity: e.velocityY` (or `velocityX`); expect velocity handed to the spring so there is no seam at release.
- Flag a distance-only dismissal threshold; expect velocity or distance, via momentum projection so a flick is enough (`project(velocity)` = `((velocity / 1000) * 0.998) / (1 - 0.998)`; the recipe dismisses at projected > 40% of height).
- Flag a hard stop at a boundary; expect rubber-band resistance (`rubberband(overshoot, dimension, 0.55)`).
- Flag a dismissal spring without `overshootClamping: true`; the sheet springs past the screen edge and flashes a gap.
- Flag a pan inside a scroll view with no axis declared; expect `activeOffsetX([-10, 10])` / `activeOffsetY([-10, 10])`, or it steals scrolls.
- Flag a gesture rebuilt every render (Gesture Handler v2); expect `useMemo`. On v3 the hook manages its own identity.
- Flag a backdrop animated separately from the sheet; expect it derived from the same shared value via `interpolate(..., Extrapolation.CLAMP)`.
- Flag custom swipe-to-reveal built from scratch; expect `ReanimatedSwipeable` unless it is swipe-to-commit with momentum projection.
- Flag a threshold crossing polled from JS or `scheduleOnRN` per frame; expect `useAnimatedReaction` comparing `isArmed !== wasArmed`.

## Layout animations, entering and exiting

- Flag `entering` on a row in `FlatList`, `FlashList` or any virtualized list; rows are recycled and re-fire on scroll-back. Expect animating the container once on mount, or `itemLayoutAnimation` for reflow only.
- Flag a layout-animation builder chained inline in JSX; expect module scope, or `useMemo` when it depends on a prop (e.g. per-index delay).
- Flag stagger outside 30-80ms (`FadeInDown.duration(250).delay(index * 40)` is the recipe form), or stagger that blocks interaction.
- Flag a toast that exits differently than it entered, or exits no faster than entry; expect same path, exit ~20% faster (recipe: enter 300ms, exit 250ms, both `EASE_OUT`).
- Flag a toast without safe-area insets (`bottom: insets.bottom + 16`).
- Flag a tab/segmented indicator that measures per frame; expect `onLayout` once, then `withTiming(..., { duration: 250, easing: EASE_IN_OUT })`.

## Screen transitions and sheets

- Flag a custom `animation` without `animationMatchesGesture: true`; the iOS back swipe then looks like a different app.
- Expect: deeper in a hierarchy `animation: 'default'`; abandonable task `presentation: 'modal'`; short interruption (picker, filter, share) `presentation: 'formSheet'` with detents; between tabs `animation: 'none'`; reduced motion `animation: 'fade'`.
- Flag `formSheet` with more than three `sheetAllowedDetents` (Android silently truncates).
- Flag reliance on `sheetGrabberVisible` as the only draggable affordance (iOS-only).
- Flag a native header or nested stack inside an Android form sheet; expect `presentation: 'modal'`.
- Flag `fitToContents` on a `flex: 1` root; expect explicitly sized content.

## Press feedback

- Flag press feedback that waits for the tap to complete; expect feedback on press-in, commit on press-out.
- Flag press scale other than ~`0.97` in 100-150ms (recipe: 120ms, `cubic-bezier(0.23, 1, 0.32, 1)`).
- Flag a touch target under 44x44pt (48dp Android) with no `hitSlop`; expect `hitSlop` rather than a bigger visual.
- Flag a pressable without `pressRetentionOffset`; finger drift cancels intended presses.
- Flag an Android ripple in a custom-designed app; expect the same scale on both platforms (ripple only in a Material-styled app).
- Flag any hover-based affordance ported from web; mobile has no hover.

## Haptics

- Flag haptics that lag the visual; expect the same frame, at the causal moment (the detent catching), not when the animation ends.
- Flag more than one haptic per user action, a haptic on scroll, per frame, or on an entrance the user didn't cause.
- Flag haptics as the only feedback; expect a visual that stands alone.
- Flag the wrong call:

| Moment | Call |
| --- | --- |
| Value ticks past a step (picker, slider detent) | `Haptics.selectionAsync()` |
| Snap home, detent catch, drag commits | `Haptics.impactAsync(ImpactFeedbackStyle.Light)` |
| Heavy object lands, destructive action | `Haptics.impactAsync(ImpactFeedbackStyle.Medium)` |
| Success / failure | `Haptics.notificationAsync(NotificationFeedbackType.Success / Error)` |

- Flag a haptic called directly from a worklet; expect `scheduleOnRN(Haptics.selectionAsync)`.

## Reduced motion and accessibility

- Flag movement with no reduced-motion handling; expect `useReducedMotion()` or `reduceMotion: ReduceMotion.System` on the animation.

```jsx
const reduced = useReducedMotion();
const y = useSharedValue(reduced ? 0 : SHEET_HEIGHT);
withSpring(0, { duration: 300, dampingRatio: 0.8, reduceMotion: ReduceMotion.System });
```

- Reduced motion is fewer and gentler, not zero: keep opacity/color that explains a state change, drop translation, scale, parallax and overshoot. Flag removal of all feedback; flag kept parallax or overshoot.

## Setup that silently breaks motion

- Flag a missing `GestureHandlerRootView` at the app root; gestures do nothing, no error.
- Flag libraries added with `npm install`; expect `npx expo install` so versions match the SDK.
- Reanimated 4 requires the New Architecture. A missing or misplaced worklets Babel plugin (bare RN only; `babel-preset-expo` handles Expo) throws `Failed to create a worklet`.

## Device testing and frame rate

- Flag "verified" in Expo Go, a dev build, or the simulator; expect a release build on the slowest supported device. A dev JS thread hides the problems being hunted.
- On ProMotion iPhones animation is capped at 60fps unless `CADisableMinimumFrameDurationOnPhone` is set. Expect it in `expo.ios.infoPlist` (recent SDKs default it; confirm). The frame budget is then 8ms, not 16.
- Gestures, velocity handoff and haptic timing can't be judged from code. Recommend: flick it, interrupt it mid-flight, reverse it, run it on the slowest Android available.
- Opacity vs reflow tuning in stacking toasts has no formula; recommend tuning by eye and looking again the next day.
