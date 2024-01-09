// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

Shader "Graphics Tools/Magnifier"
{
    Properties
    {
        [Header(Sharpening)]
        // Choose a kernal sample pattern.
        [KeywordEnum(None, Fast, Normal, Wider, Pyramid, PyramidSlow, PyramidSlow2)] _sharp_kernal ("Kernal", Float) = 2

        // [0.10 to 3.00] Strength of the sharpening.
        _sharp_strength ("Strength", Range(0.1, 3.0)) = 1.25
        
        // [0.000 to 1.000] Limits maximum amount of sharpening a pixel recieves - Default is 0.035.
        _sharp_clamp ("Clamp", Range(0.0, 1.0)) = 0.035

        // [0.0 to 6.0] Offset bias adjusts the radius of the sampling pattern.
        _sharp_offset_bias ("Offset Bias", Range(0.0, 6.0)) = 1.0
    }
    SubShader
    {
        PackageRequirements
        {
            "com.unity.render-pipelines.universal": "12.1.0"
        }

        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // Comment in to help with RenderDoc debugging.
            //#pragma enable_d3d11_debug_symbols

            #pragma multi_compile _SHARP_KERNAL_NONE _SHARP_KERNAL_FAST _SHARP_KERNAL_NORMAL _SHARP_KERNAL_WIDER _SHARP_KERNAL_PYRAMID _SHARP_KERNAL_PYRAMIDSLOW _SHARP_KERNAL_PYRAMIDSLOW2

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;

                UNITY_VERTEX_OUTPUT_STEREO
            };

            TEXTURE2D_X(MagnifierTexture);
            SAMPLER(samplerMagnifierTexture);
            float4 MagnifierTexture_TexelSize;

            half MagnifierMagnification;
            float4 MagnifierCenter;

CBUFFER_START(UnityPerMaterial)
            float _sharp_strength;
            float _sharp_clamp;
            float _sharp_offset_bias;
 CBUFFER_END

            float2 ZoomIn(float2 uv, float zoomAmount, float2 zoomCenter)
            {
                return ((uv - zoomCenter) * zoomAmount) + zoomCenter;
            }

            #define CoefLuma float3(0.2126, 0.7152, 0.0722)      // BT.709 & sRBG luma coefficient (Monitors and HD Television)
            //#define CoefLuma float3(0.299, 0.587, 0.114)       // BT.601 luma coefficient (SD Television)
            //#define CoefLuma float3(1.0/3.0, 1.0/3.0, 1.0/3.0) // Equal weight coefficient

            // Source: https://github.com/zachsaw/RenderScripts/blob/master/RenderScripts/ImageProcessingShaders/SweetFX/LumaSharpen.hlsl
            float4 LumaSharpenPass(float4 inputcolor, float2 tex)
            {
                // Don't perform any sharpening.
#if defined(_SHARP_KERNAL_NONE)
                    return inputcolor;
#else
                // -- Get the original pixel --
                float3 ori = inputcolor.rgb;       // ori = original pixel

                // -- Combining the strength and luma multipliers --
                float3 sharp_strength_luma = (CoefLuma * _sharp_strength); //I'll be combining even more multipliers with it later on

                float px = MagnifierTexture_TexelSize.x;
                float py = MagnifierTexture_TexelSize.y;

                //   [ NW,   , NE ] Each texture lookup (except ori)
                //   [   ,ori,    ] samples 4 pixels
                //   [ SW,   , SE ]
                
                // -- Pattern 1 -- A (fast) 7 tap gaussian using only 2+1 texture fetches.
#if defined(_SHARP_KERNAL_FAST)
                
                // -- Gaussian filter --
                //   [ 1/9, 2/9,    ]     [ 1 , 2 ,   ]
                //   [ 2/9, 8/9, 2/9]  =  [ 2 , 8 , 2 ]
           	    //   [    , 2/9, 1/9]     [   , 2 , 1 ]
                
                  float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + (float2(px,py) / 3.0) * _sharp_offset_bias).rgb;  // North West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + (float2(-px,-py) / 3.0) * _sharp_offset_bias).rgb; // South East
                
                  //blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,py) / 3.0 * _sharp_offset_bias); // North East
                  //blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,-py) / 3.0 * _sharp_offset_bias); // South West
                
                  blur_ori /= 2;  //Divide by the number of texture fetches
                
                  sharp_strength_luma *= 1.5; // Adjust strength to aproximate the strength of pattern 2
                
#endif // _SHARP_KERNAL_FAST
                
                // -- Pattern 2 -- A 9 tap gaussian using 4+1 texture fetches.
#if defined(_SHARP_KERNAL_NORMAL)
                
                // -- Gaussian filter --
                //   [ .25, .50, .25]     [ 1 , 2 , 1 ]
                //   [ .50,   1, .50]  =  [ 2 , 4 , 2 ]
           	    //   [ .25, .50, .25]     [ 1 , 2 , 1 ]
                
                
                  float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,-py) * 0.5 * _sharp_offset_bias).rgb; // South East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,-py) * 0.5 * _sharp_offset_bias).rgb;  // South West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,py) * 0.5 * _sharp_offset_bias).rgb; // North East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,py) * 0.5 * _sharp_offset_bias).rgb; // North West
                
                  blur_ori *= 0.25;  // ( /= 4) Divide by the number of texture fetches
                
#endif // _SHARP_KERNAL_NORMAL
                
                // -- Pattern 3 -- An experimental 17 tap gaussian using 4+1 texture fetches.
#if defined(_SHARP_KERNAL_WIDER)
                
                // -- Gaussian filter --
                //   [   , 4 , 6 ,   ,   ]
                //   [   ,16 ,24 ,16 , 4 ]
                //   [ 6 ,24 ,   ,24 , 6 ]
                //   [ 4 ,16 ,24 ,16 ,   ]
                //   [   ,   , 6 , 4 ,   ]
                
                  float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0.4*px,-1.2*py)* _sharp_offset_bias).rgb;  // South South East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-1.2*px,-0.4*py) * _sharp_offset_bias).rgb; // West South West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(1.2*px,0.4*py) * _sharp_offset_bias).rgb; // East North East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-0.4*px,1.2*py) * _sharp_offset_bias).rgb; // North North West
                
                  blur_ori *= 0.25;  // ( /= 4) Divide by the number of texture fetches
                
                  sharp_strength_luma *= 0.51;
#endif // _SHARP_KERNAL_WIDER
                
                // -- Pattern 4 -- A 9 tap high pass (pyramid filter) using 4+1 texture fetches.
#if defined(_SHARP_KERNAL_PYRAMID)
                
                // -- Gaussian filter --
                //   [ .50, .50, .50]     [ 1 , 1 , 1 ]
                //   [ .50,    , .50]  =  [ 1 ,   , 1 ]
           	    //   [ .50, .50, .50]     [ 1 , 1 , 1 ]
                
                  float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0.5 * px,-py * _sharp_offset_bias)).rgb;  // South South East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(_sharp_offset_bias * -px,0.5 * -py)).rgb; // West South West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(_sharp_offset_bias * px,0.5 * py)).rgb; // East North East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0.5 * -px,py * _sharp_offset_bias)).rgb; // North North West
                
                  //blur_ori += (2 * ori); // Probably not needed. Only serves to lessen the effect.
                
                  blur_ori /= 4.0;  //Divide by the number of texture fetches
                
                  sharp_strength_luma *= 0.666; // Adjust strength to aproximate the strength of pattern 2
#endif // _SHARP_KERNAL_PYRAMID
                
                // -- Pattern 8 -- A (slower) 9 tap gaussian using 9 texture fetches.
#if defined(_SHARP_KERNAL_PYRAMIDSLOW)
                
                // -- Gaussian filter --
                //   [ 1 , 2 , 1 ]
                //   [ 2 , 4 , 2 ]
           	    //   [ 1 , 2 , 1 ]
                
                  half3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,py) * _sharp_offset_bias).rgb; // North West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,-py) * _sharp_offset_bias).rgb;     // South East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,-py)  * _sharp_offset_bias).rgb;  // South West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,py) * _sharp_offset_bias).rgb;    // North East
                
                  half3 blur_ori2 = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0,py) * _sharp_offset_bias).rgb; // North
                  blur_ori2 += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0,-py) * _sharp_offset_bias).rgb;    // South
                  blur_ori2 += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,0) * _sharp_offset_bias).rgb;   // West
                  blur_ori2 += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,0) * _sharp_offset_bias).rgb;   // East
                  blur_ori2 *= 2.0;
                
                  blur_ori += blur_ori2;
                  blur_ori += (ori * 4); // Probably not needed. Only serves to lessen the effect.
                
                  // dot()s with gaussian strengths here?
                
                  blur_ori /= 16.0;  //Divide by the number of texture fetches
                
                  //sharp_strength_luma *= 0.75; // Adjust strength to aproximate the strength of pattern 2
#endif // _SHARP_KERNAL_PYRAMIDSLOW
                
                // -- Pattern 9 -- A (slower) 9 tap high pass using 9 texture fetches.
#if defined(_SHARP_KERNAL_PYRAMIDSLOW2)
                
                // -- Gaussian filter --
                //   [ 1 , 1 , 1 ]
                //   [ 1 , 1 , 1 ]
           	    //   [ 1 , 1 , 1 ]
                
                  float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,py) * _sharp_offset_bias).rgb; // North West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,-py) * _sharp_offset_bias).rgb;     // South East
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,-py)  * _sharp_offset_bias).rgb;  // South West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,py) * _sharp_offset_bias).rgb;    // North East
                
                  blur_ori += ori.rgb; // Probably not needed. Only serves to lessen the effect.
                
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0,py) * _sharp_offset_bias).rgb;    // North
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(0,-py) * _sharp_offset_bias).rgb;  // South
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(-px,0) * _sharp_offset_bias).rgb; // West
                  blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, tex + float2(px,0) * _sharp_offset_bias).rgb; // East
                
                  blur_ori /= 9;  //Divide by the number of texture fetches
                
                  //sharp_strength_luma *= (8.0/9.0); // Adjust strength to aproximate the strength of pattern 2
#endif // _SHARP_KERNAL_PYRAMIDSLOW2

                // -- Calculate the sharpening --
                float3 sharp = ori - blur_ori;  //Subtracting the blurred image from the original image

                // -- Adjust strength of the sharpening and clamp it--
                float4 sharp_strength_luma_clamp = float4(sharp_strength_luma * (0.5 / _sharp_clamp),0.5); //Roll part of the clamp into the dot
                
                //sharp_luma = saturate((0.5 / sharp_clamp) * sharp_luma + 0.5); //scale up and clamp
                float sharp_luma = saturate(dot(float4(sharp,1.0), sharp_strength_luma_clamp)); //Calculate the luma, adjust the strength, scale up and clamp
                sharp_luma = (_sharp_clamp * 2.0) * sharp_luma - _sharp_clamp; //scale down
                
                // -- Combining the values to get the final sharpened pixel	--
                //float4 done = ori + sharp_luma;    // Add the sharpening to the original.
                inputcolor.rgb = inputcolor.rgb + sharp_luma;    // Add the sharpening to the input color.
                
                return saturate(inputcolor);
#endif // _SHARP_KERNAL_NONE
            }

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = TransformObjectToHClip(v.vertex.xyz);

                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float2 normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.vertex);
                float2 normalizedScreenSpaceUVStereo = UnityStereoTransformScreenSpaceTex(normalizedScreenSpaceUV);
                float2 zoomedUv = ZoomIn(normalizedScreenSpaceUVStereo, MagnifierMagnification, MagnifierCenter.xy);

                return LumaSharpenPass(SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, zoomedUv), zoomedUv);
            }
           ENDHLSL
        }
    }

    Fallback "Hidden/InternalErrorShader"
}