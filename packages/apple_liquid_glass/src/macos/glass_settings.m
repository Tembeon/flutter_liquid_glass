#import <Accessibility/Accessibility.h>
#import <AppKit/AppKit.h>

#import "glass_platform.h"

int glass_reduce_transparency(void) {
  return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency ? 1 : 0;
}

int glass_show_borders(void) {
  if (@available(macOS 26.1, *)) return AXShowBordersEnabled() ? 1 : 0;
  return 0;
}

int glass_prefers_cross_fade(void) {
  return -1;
}

int glass_reduce_highlighting(void) {
  if (@available(macOS 26.4, *)) return AXReduceHighlightingEffectsEnabled() ? 1 : 0;
  return -1;
}

int glass_prefers_reduced_resource_usage(void) {
  return -1;
}

double glass_tint_amount(void) {
  return -1;
}

static NSArray<NSArray *> *glassSettingsObservers;

void glass_observe_settings(void (^changed)(void)) {
  for (NSArray *pair in glassSettingsObservers) [pair[0] removeObserver:pair[1]];
  // AppKit posts display option changes to the workspace's own center.
  NSMutableArray<NSArray *> *sources = [NSMutableArray arrayWithObject:@[
    NSWorkspace.sharedWorkspace.notificationCenter,
    NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification,
  ]];
  if (@available(macOS 26.1, *)) {
    [sources addObject:@[
      NSNotificationCenter.defaultCenter,
      AXShowBordersEnabledStatusDidChangeNotification,
    ]];
  }
  if (@available(macOS 26.4, *)) {
    [sources addObject:@[
      NSNotificationCenter.defaultCenter,
      AXReduceHighlightingEffectsEnabledDidChangeNotification,
    ]];
  }
  NSMutableArray<NSArray *> *observers = [NSMutableArray array];
  for (NSArray *source in sources) {
    NSNotificationCenter *center = source[0];
    id<NSObject> observer = [center addObserverForName:source[1]
                                                object:nil
                                                 queue:NSOperationQueue.mainQueue
                                            usingBlock:^(NSNotification *note) {
                                              changed();
                                            }];
    [observers addObject:@[ center, observer ]];
  }
  glassSettingsObservers = observers;
}
