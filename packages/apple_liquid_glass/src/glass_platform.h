#import <Foundation/Foundation.h>

#define GLASS_EXPORT __attribute__((visibility("default"))) __attribute__((used))

GLASS_EXPORT int glass_is_main_thread(void);

// iOS only.
GLASS_EXPORT void *glass_controller_of_engine(int64_t identifier);
GLASS_EXPORT void *glass_controller_of_scenes(void);
GLASS_EXPORT void glass_install_hinge(void *view, void *interaction);
GLASS_EXPORT int glass_set_vertical_bar_behavior(void *controller, int64_t behavior);

// The settings Flutter does not report: 1 on, 0 off, -1 where the platform
// says nothing.
GLASS_EXPORT int glass_reduce_transparency(void);
GLASS_EXPORT int glass_show_borders(void);
GLASS_EXPORT int glass_prefers_cross_fade(void);
GLASS_EXPORT int glass_prefers_reduced_resource_usage(void);

// Where the Liquid Glass slider stands, from 0 to 1, or -1 where the platform
// says nothing.
GLASS_EXPORT double glass_tint_amount(void);

// Calls changed on the main thread whenever one of the settings may have
// changed, in place of the block given before, which a hot restart leaves
// behind.
GLASS_EXPORT void glass_observe_settings(void (^changed)(void));
