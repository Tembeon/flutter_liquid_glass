#import <Accessibility/Accessibility.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import "glass_platform.h"

// The Liquid Glass slider of iOS 27 (Settings, Appearance): UIKit exports its
// getter and change notification without declaring them, so they are looked
// up at run time and missing before iOS 27 or once UIKit drops them. The
// getter returns the slider as a number, 0.5 while it was never moved.
typedef id (*GlassTintAmountGetter)(void);

static GlassTintAmountGetter glass_tint_amount_getter(void) {
  static GlassTintAmountGetter getter;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    getter = (GlassTintAmountGetter)dlsym(RTLD_DEFAULT, "UIViewGlassGetTintAmount");
  });
  return getter;
}

static NSNotificationName glass_tint_amount_did_change(void) {
  void *symbol = dlsym(RTLD_DEFAULT, "UIViewGlassTintAmountDidChangeNotification");
  return symbol == NULL ? nil : *(NSNotificationName __unsafe_unretained const *)symbol;
}

int glass_reduce_transparency(void) {
  return UIAccessibilityIsReduceTransparencyEnabled() ? 1 : 0;
}

int glass_show_borders(void) {
  if (@available(iOS 26.1, *)) return AXShowBordersEnabled() ? 1 : 0;
  if (@available(iOS 14.0, *)) return UIAccessibilityButtonShapesEnabled() ? 1 : 0;
  return -1;
}

int glass_prefers_cross_fade(void) {
  if (@available(iOS 14.0, *)) return UIAccessibilityPrefersCrossFadeTransitions() ? 1 : 0;
  return -1;
}

int glass_prefers_reduced_resource_usage(void) {
  if (@available(iOS 27.0, *)) {
    return UIApplication.sharedApplication.systemPrefersReducedResourceUsage ? 1 : 0;
  }
  return -1;
}

double glass_tint_amount(void) {
  GlassTintAmountGetter getter = glass_tint_amount_getter();
  if (getter == NULL) return -1;
  id amount = getter();
  return [amount isKindOfClass:[NSNumber class]] ? [amount doubleValue] : -1;
}

static NSArray<id<NSObject>> *glassSettingsObservers;

void glass_observe_settings(void (^changed)(void)) {
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  for (id<NSObject> observer in glassSettingsObservers) [center removeObserver:observer];
  NSMutableArray<NSNotificationName> *names =
      [NSMutableArray arrayWithObject:UIAccessibilityReduceTransparencyStatusDidChangeNotification];
  if (@available(iOS 14.0, *)) {
    [names addObject:UIAccessibilityPrefersCrossFadeTransitionsStatusDidChangeNotification];
  }
  if (@available(iOS 26.1, *)) {
    [names addObject:AXShowBordersEnabledStatusDidChangeNotification];
  } else if (@available(iOS 14.0, *)) {
    [names addObject:UIAccessibilityButtonShapesEnabledStatusDidChangeNotification];
  }
  NSNotificationName tint = glass_tint_amount_did_change();
  if (tint != nil) [names addObject:tint];
  if (@available(iOS 27.0, *)) {
    [names addObject:UIApplicationSystemPrefersReducedResourceUsageDidChangeNotification];
  }
  NSMutableArray<id<NSObject>> *observers = [NSMutableArray array];
  for (NSNotificationName name in names) {
    [observers addObject:[center addObserverForName:name
                                             object:nil
                                              queue:NSOperationQueue.mainQueue
                                         usingBlock:^(NSNotification *note) {
                                           changed();
                                         }]];
  }
  glassSettingsObservers = observers;
}
