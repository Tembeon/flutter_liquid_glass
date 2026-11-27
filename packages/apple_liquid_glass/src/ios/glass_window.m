#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "glass_platform.h"

// FlutterEngine keeps engineForIdentifier: in its internal header, so it is
// asked for at run time.
void *glass_controller_of_engine(int64_t identifier) {
  Class engineClass = NSClassFromString(@"FlutterEngine");
  SEL lookup = NSSelectorFromString(@"engineForIdentifier:");
  if (![engineClass respondsToSelector:lookup]) return NULL;
  id engine = ((id(*)(id, SEL, int64_t))objc_msgSend)(engineClass, lookup, identifier);
  SEL controllerSelector = NSSelectorFromString(@"viewController");
  if (![engine respondsToSelector:controllerSelector]) return NULL;
  id controller = ((id(*)(id, SEL))objc_msgSend)(engine, controllerSelector);
  if (![controller isKindOfClass:[UIViewController class]]) return NULL;
  return (__bridge void *)controller;
}

void *glass_controller_of_scenes(void) {
  Class flutterController = NSClassFromString(@"FlutterViewController");
  if (flutterController == nil) return NULL;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      UIViewController *root = window.rootViewController;
      if ([root isKindOfClass:flutterController]) return (__bridge void *)root;
    }
  }
  return NULL;
}

// The interaction outlives a hot restart, which starts Dart over: the one
// installed last is kept here and taken off its view when another comes.
static id<UIInteraction> glassHinge;

void glass_install_hinge(void *view, void *interaction) {
  id<UIInteraction> previous = glassHinge;
  if (previous != nil) [previous.view removeInteraction:previous];
  glassHinge = (__bridge id<UIInteraction>)interaction;
  [(__bridge UIView *)view addInteraction:glassHinge];
}

static char glassVerticalBarBehaviorKey;

static NSInteger GlassPreferredVerticalBarBehavior(id self, SEL _cmd) {
  NSNumber *behavior = objc_getAssociatedObject(self, &glassVerticalBarBehaviorKey);
  return behavior.integerValue;
}

// UIKit asks the root view controller for its vertical bar behavior and
// FlutterViewController has no answer of its own, so one is added to its
// class. It answers at once from the value kept on the controller, and never
// calls Dart, which may be gone after a hot restart. A class that answers
// already, a runner's subclass, keeps its answer, and a window with no
// column leaves the class as it is until one shows.
int glass_set_vertical_bar_behavior(void *controller, int64_t behavior) {
  if (@available(iOS 27.1, *)) {
    UIViewController *viewController = (__bridge UIViewController *)controller;
    NSNumber *previous = objc_getAssociatedObject(viewController, &glassVerticalBarBehaviorKey);
    if (previous.integerValue == behavior) return 1;
    if (previous == nil &&
        viewController.traitCollection.verticalBarEdge == UIVerticalBarEdgeUnspecified) {
      return 0;
    }
    SEL selector = @selector(preferredVerticalBarBehavior);
    Class cls = [viewController class];
    IMP implementation = (IMP)GlassPreferredVerticalBarBehavior;
    Method current = class_getInstanceMethod(cls, selector);
    if (method_getImplementation(current) != implementation &&
        !class_addMethod(cls, selector, implementation, method_getTypeEncoding(current))) {
      return 0;
    }
    objc_setAssociatedObject(viewController, &glassVerticalBarBehaviorKey, @(behavior),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [viewController setNeedsUpdateOfVerticalBarConfiguration];
    return 1;
  }
  return 0;
}
