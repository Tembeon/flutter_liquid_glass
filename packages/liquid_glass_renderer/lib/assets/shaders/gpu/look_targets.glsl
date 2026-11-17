// Impeller's OpenGL ES backend draws into one color attachment, so there the
// atlas and each look take a pass of their own.

#ifdef LOOK_ONLY
void writeLook(Look look) {
#if LOOK_ONLY == 1
    fragColor = look.tint;
#elif LOOK_ONLY == 2
    fragColor = look.response;
#elif LOOK_ONLY == 3
    fragColor = look.weights;
#endif
}
#else
layout(location = 1) out vec4 lookTint;
#if LOOKS > 1
layout(location = 2) out vec4 lookResponse;
layout(location = 3) out vec4 lookWeights;
#endif

void writeLook(Look look) {
    lookTint = look.tint;
#if LOOKS > 1
    lookResponse = look.response;
    lookWeights = look.weights;
#endif
}
#endif
