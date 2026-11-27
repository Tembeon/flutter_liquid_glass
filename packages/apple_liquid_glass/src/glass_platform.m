#import "glass_platform.h"

int glass_is_main_thread(void) {
  return [NSThread isMainThread] ? 1 : 0;
}
