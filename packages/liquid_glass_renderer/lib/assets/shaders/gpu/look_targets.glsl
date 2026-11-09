// The atlas pass's targets beside the geometry: the tint alone (LOOKS 1),
// or the whole look (LOOKS 2), at the geometry's texels.

layout(location = 1) out vec4 lookTint;
#if LOOKS > 1
layout(location = 2) out vec4 lookResponse;
layout(location = 3) out vec4 lookShares;
#endif

void writeLook(Look look) {
    lookTint = look.tint;
#if LOOKS > 1
    lookResponse = look.response;
    lookShares = look.shares;
#endif
}
