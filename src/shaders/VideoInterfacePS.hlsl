//
// RT64
//

#include "shared/rt64_video_interface.h"

[[vk::push_constant]] ConstantBuffer<VideoInterfaceCB> gConstants : register(b0);
Texture2D<float4> gInput : register(t1);
SamplerState gSampler : register(s2);

// Limit texture sampling to the area the VI can sample of the texture.

float4 SampleInput(float2 uv) {
    const float2 LowerRight = gConstants.videoResolution / gConstants.textureResolution;
    const float2 HalfPixel = float2(0.5f, 0.5f) / gConstants.textureResolution;
    float2 outsideBorder = step(LowerRight, uv);
    float4 sampledColor = gInput.SampleLevel(gSampler, clamp(uv, HalfPixel, LowerRight - HalfPixel), 0);
    float4 gammaCorrectedColor = pow(sampledColor, gConstants.gamma);
    gammaCorrectedColor.rgb *= max(1.0f - outsideBorder.x - outsideBorder.y, 0.0f);
    gammaCorrectedColor.a = 1.0f;
    return gammaCorrectedColor;
}

//
// Sourced from https://www.shadertoy.com/view/csX3RH
//
float4 PixelAntialiasing(float2 uv) {
    float2 uvTexspace = uv * gConstants.videoResolution;
    float2 seam = floor(uvTexspace + 0.5f);
    uvTexspace = (uvTexspace - seam) / fwidth(uvTexspace) + seam;
    uvTexspace = clamp(uvTexspace, seam - 0.5f, seam + 0.5f);
    return SampleInput(uvTexspace / gConstants.textureResolution);
}

// Barrel distortion. 0 leaves the image untouched.
float2 WarpCurvature(float2 uv) {
    if (gConstants.crtCurvature <= 0.0f) {
        return uv;
    }

    float2 centered = uv - 0.5f;
    float radiusSquared = dot(centered, centered);
    return uv + centered * radiusSquared * gConstants.crtCurvature * 0.5f;
}

float4 ApplyCRT(float4 color, float2 uv) {
    if (gConstants.crtMode == 0) {
        return color;
    }

    // Scanlines follow the console's native line count (240 for NTSC), not the
    // output resolution, so the pattern stays stable when the window is scaled.
    const float TwoPi = 6.28318530718f;
    float linePhase = uv.y * max(gConstants.sourceResolution.y, 1.0f);
    float scan = 0.5f + 0.5f * cos(TwoPi * linePhase);
    float scanMultiplier = 1.0f - gConstants.crtScanlineIntensity * 0.8f * (1.0f - scan);
    color.rgb *= scanMultiplier;

    // Phosphor masks. x/y are in output pixels so the pattern is one pixel wide
    // at the internal render resolution.
    float2 pixel = uv * gConstants.videoResolution;
    float3 mask = float3(1.0f, 1.0f, 1.0f);
    if (gConstants.crtMode == 2) {
        // Aperture grille: vertical RGB stripes.
        float m = fmod(floor(pixel.x), 3.0f);
        mask = (m < 1.0f) ? float3(1.0f, 0.55f, 0.55f)
             : (m < 2.0f) ? float3(0.55f, 1.0f, 0.55f)
             : float3(0.55f, 0.55f, 1.0f);
    }
    else if (gConstants.crtMode == 3) {
        // Shadow mask: 2x2 RGB-ish grid.
        float2 m = float2(fmod(floor(pixel.x), 2.0f), fmod(floor(pixel.y), 2.0f));
        if (m.x < 1.0f && m.y < 1.0f) {
            mask = float3(1.0f, 0.45f, 0.45f);
        }
        else if (m.x >= 1.0f && m.y < 1.0f) {
            mask = float3(0.45f, 1.0f, 0.45f);
        }
        else if (m.x < 1.0f && m.y >= 1.0f) {
            mask = float3(0.45f, 0.45f, 1.0f);
        }
        else {
            mask = float3(0.80f, 0.80f, 0.80f);
        }
    }
    else if (gConstants.crtMode == 4) {
        // Slot mask: 3x2 staggered.
        float2 m = float2(fmod(floor(pixel.x), 3.0f), fmod(floor(pixel.y), 2.0f));
        if (m.y < 1.0f) {
            mask = (m.x < 1.0f) ? float3(1.0f, 0.50f, 0.50f)
                 : (m.x < 2.0f) ? float3(0.50f, 1.0f, 0.50f)
                 : float3(0.50f, 0.50f, 1.0f);
        }
        else {
            mask = (m.x < 1.0f) ? float3(0.50f, 0.50f, 1.0f)
                 : (m.x < 2.0f) ? float3(1.0f, 0.50f, 0.50f)
                 : float3(0.50f, 1.0f, 0.50f);
        }
    }
    color.rgb *= lerp(float3(1.0f, 1.0f, 1.0f), mask, gConstants.crtMaskIntensity);

    // Soft edge falloff.
    if (gConstants.crtVignette > 0.0f) {
        float2 centered = uv - 0.5f;
        float vignette = saturate(1.0f - gConstants.crtVignette * dot(centered, centered) * 1.5f);
        color.rgb *= vignette;
    }

    return color;
}

float4 PSMain(in float4 pos : SV_Position, in float2 uv : TEXCOORD0) : SV_TARGET {
    float2 warpedUV = WarpCurvature(uv);

#ifdef PIXEL_ANTIALIASING
    float4 color = PixelAntialiasing(warpedUV);
#else
    float4 color = SampleInput((warpedUV / gConstants.textureResolution) * gConstants.videoResolution);
#endif

    return ApplyCRT(color, uv);
}
