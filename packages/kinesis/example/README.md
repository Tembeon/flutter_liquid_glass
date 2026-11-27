# kinesis example

A catalog of what kinesis does, one page per part of the library: springs and
timing curves, keyframes and animators, what happens on release, text and
symbol effects, layout changes, scroll, visibility and the caret,
interactions and input zones, and presentations. Each page shows one feature
with the least code that uses it and says in a line what to try.

It is built on `package:flutter/widgets.dart` and kinesis alone: no Material
or Cupertino widgets and no `AnimationController`.

```sh
flutter run
```

`lib/kit.dart` holds the catalog's own look (colors, text styles, cards and
buttons), and each page is a file in `lib/demos/`. `test/gallery_test.dart`
opens every page at a narrow and a wide size, presses its buttons and drives
the gestures each page describes.
