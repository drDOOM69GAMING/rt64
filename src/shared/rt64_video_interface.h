//
// RT64
//

#pragma once

#include "shared/rt64_hlsl.h"

#ifdef HLSL_CPU
namespace interop {
#endif
    struct VideoInterfaceCB {
        float2 videoResolution;
        float2 textureResolution;
        // Native VI size in scanlines (e.g. 320x240). Used to place CRT scanlines
        // at the original line count regardless of the output scale.
        float2 sourceResolution;
        float gamma;
        // 0 = off, 1 = scanlines, 2 = aperture grille, 3 = shadow mask, 4 = slot mask.
        uint crtMode;
        float crtScanlineIntensity;
        float crtMaskIntensity;
        float crtCurvature;
        float crtVignette;
        float4 _padding;
    };
#ifdef HLSL_CPU
};
#endif
