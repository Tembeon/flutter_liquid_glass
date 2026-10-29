# Apple Liquid Glass Accessibility

Feeds the iOS and macOS accessibility settings that Flutter does not report
into `apple_liquid_glass`: Reduce Transparency, Show Borders (Button Shapes
before iOS 26.1) and Prefer Cross-Fade Transitions.

Unpublished prerelease; the API may change.

## Usage

Wrap the app in a `GlassPlatformTraits`, or return one from
`WidgetsApp.builder` so presented content sees the settings too:

```dart
WidgetsApp(
  color: const Color(0xFF007AFF),
  builder: (context, child) => GlassPlatformTraits(child: child!),
  home: const HomePage(),
);
```

Glass then draws flat under Reduce Transparency, outlines its surfaces under
Show Borders and, with Reduce Motion, cross-fades pages as Prefer Cross-Fade
Transitions says. The settings reach the subtree as `GlassTraits`; until the
platform reports them, and on other platforms, the enclosing traits stay.

To read the settings without glass, listen to
`AppleAccessibilityFeatures.watch()`: it gives the current settings, then
each change.

macOS reports Show Borders from 26.1 and has no Prefer Cross-Fade
Transitions setting; there `prefersCrossFade` is null and cross-fading
follows Reduce Motion, as it does on iOS by default.
