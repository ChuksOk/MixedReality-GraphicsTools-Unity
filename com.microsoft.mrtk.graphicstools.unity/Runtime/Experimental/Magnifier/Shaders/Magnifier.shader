// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

Shader"Graphics Tools/Magnifier"
{
    Properties
    {
        _Sharpening ("Sharpening", Range(0.0, 5.0)) = 1
        _Edge ("Edge", Range(0.01, 10.0)) = 1.0
        _Threshold ("Threshold", Range(0.0, 1.0)) = 0.5
        _Smoothness ("Smoothness", Range(0.0, 1.0)) = 0.5
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
            #pragma enable_d3d11_debug_symbols
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

#define s2(a, b)				temp = a; a = min(a, b); b = max(temp, b);
#define mn3(a, b, c)			s2(a, b); s2(a, c);
#define mx3(a, b, c)			s2(b, c); s2(a, c);

#define mnmx3(a, b, c)				mx3(a, b, c); s2(a, b);                                   // 3 exchanges
#define mnmx4(a, b, c, d)			s2(a, b); s2(c, d); s2(a, c); s2(b, d);                   // 4 exchanges
#define mnmx5(a, b, c, d, e)		s2(a, b); s2(c, d); mn3(a, c, e); mx3(b, d, e);           // 6 exchanges
#define mnmx6(a, b, c, d, e, f) 	s2(a, d); s2(b, e); s2(c, f); mn3(a, b, c); mx3(d, e, f); // 7 exchanges
        
static const float4 ONES = (float4)1.0;// float4(1.0, 1.0, 1.0, 1.0);
static const float4 ZEROES = (float4)0.0;



//Start Sharpen variables
// -- Sharpening --
//#define sharp_clamp    0.25  //[0.000 to 1.000] Limits maximum amount of sharpening a pixel recieves - Default is 0.035
// -- Advanced sharpening settings --
//#define offset_bias 1.0  //[0.0 to 6.0] Offset bias adjusts the radius of the sampling pattern.
                         //I designed the pattern for offset_bias 1.0, but feel free to experiment.

            float offset_bias = 1.0;
            float sharp_clamp = 1.0;

            //End sharpen variables

            // Mean of Rec. 709 & 601 luma coefficients
            #define lumacoeff        float3(0.2558, 0.6511, 0.0931)
            #define HALF_MAX 65504.0
            inline half3 SafeHDR(half3 c) { return min(c, HALF_MAX); }
            inline half4 SafeHDR(half4 c) { return min(c, HALF_MAX); }

                    struct appdata
                    {
                        float4 vertex : POSITION;
                        float2 texcoord : TEXCOORD0;
	                    float2 texcoord1 : TEXCOORD1;
                        UNITY_VERTEX_INPUT_INSTANCE_ID
                    };

                    struct v2f
                    {
                        float4 vertex : SV_POSITION;
                        float2 uv : TEXCOORD0;
                        UNITY_VERTEX_OUTPUT_STEREO
                    };

            half MagnifierMagnification;
            float4 MagnifierCenter;
            float _Sharpening;
            float _Edge;
            float _Threshold;
            float _Smoothness;
            TEXTURE2D_X(MagnifierTexture);
            SAMPLER(samplerMagnifierTexture);
            half4 samplerMagnifierTexture_ST;
            half4 samplerMagnifierTexture_TexelSize;


            float2 ZoomIn(float2 uv, float zoomAmount, float2 zoomCenter)
            {
                return ((uv - zoomCenter) * zoomAmount) + zoomCenter;
            }

            float4 SampleInput(int2 coord)
            {
             float2 coordNorm = min(max(0, coord), _ScreenSize.xy - 1) / _ScreenSize.xy;
             return SAMPLE_TEXTURE2D_X(MagnifierTexture, samplerMagnifierTexture, coordNorm);
}

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                 o.uv =v.texcoord;
                return o;
            }

half4 sharpen(float2 uv)
{
	float4 colorInput = SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture, (uv));
	half2 PixelSize = samplerMagnifierTexture_TexelSize.xy;
  	
	float3 ori = colorInput.rgb;

	// -- Combining the strength and luma multipliers --
	float3 sharp_strength_luma = (lumacoeff * _Sharpening); //I'll be combining even more multipliers with it later on
	
	// -- Gaussian filter --
	//   [ .25, .50, .25]     [ 1 , 2 , 1 ]
	//   [ .50,   1, .50]  =  [ 2 , 4 , 2 ]
 	//   [ .25, .50, .25]     [ 1 , 2 , 1 ]
    float px = 1/1920;//1.0/
	float py = 1/1080;

	float3 blur_ori = SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture, (uv + float2(px, -py) * 0.5 * offset_bias)).rgb; // South East
	blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture, (uv + float2(-px, -py) * 0.5 * offset_bias)).rgb;  // South West
	blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture, (uv + float2(px, py) * 0.5 * offset_bias)).rgb; // North East
	blur_ori += SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture, (uv + float2(-px, py) * 0.5 * offset_bias)).rgb; // North West

	blur_ori *= 0.25;  // ( /= 4) Divide by the number of texture fetches

	// -- Calculate the sharpening --
	float3 sharp = ori - blur_ori;  //Subtracting the blurred image from the original image

	// -- Adjust strength of the sharpening and clamp it--
	float4 sharp_strength_luma_clamp = float4(sharp_strength_luma * (0.05 / sharp_clamp),5); //Roll part of the clamp into the dot

	float sharp_luma = clamp((dot(float4(sharp,1.0), sharp_strength_luma_clamp)), 0.5,1.0 ); //Calculate the luma, adjust the strength, scale up and clamp
	sharp_luma = (sharp_clamp * 20.0) * sharp_luma; //scale down

	// -- Combining the values to get the final sharpened pixel	--
	colorInput.rgb = colorInput.rgb + sharp_luma;    // Add the sharpening to the input color.
	
	return saturate(colorInput);
}

            half4 frag(v2f i) : SV_Target
            {
                float2 normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.vertex);
                float2 normalizedScreenSpaceUVStereo = UnityStereoTransformScreenSpaceTex(normalizedScreenSpaceUV);
                float2 zoomedUv = ZoomIn(normalizedScreenSpaceUVStereo, MagnifierMagnification, MagnifierCenter.xy);
              //  if(_Sharpening<=0)
                {
              //      return SAMPLE_TEXTURE2D_X(MagnifierTexture,samplerMagnifierTexture,zoomedUv);
                }
               return sharpen(zoomedUv);
               
              
    
             /*   int2 positionSS = zoomedUv * _ScreenSize.xy;
  half horizEdge = SampleInput(positionSS+float2(-1,0)*_Edge).r *2.0 - SampleInput(positionSS+float2(1,0)*_Edge).r*2.0;
half vertEdge = SampleInput(positionSS+float2(0,-1)*_Edge).r *2.0 - SampleInput(positionSS+float2(0,1)*_Edge).r*2.0;
half edge = sqrt(horizEdge*horizEdge +vertEdge*vertEdge);
half4 thresholdEdge = (edge>_Threshold) ? 1.0 : 0.0;
                 float4 c0 = SampleInput(positionSS + int2(-1, -1));
                 float4 c1 = SampleInput(positionSS + int2(0, -1));
                 float4 c2 = SampleInput(positionSS + int2(+1, -1));

                 float4 c3 = SampleInput(positionSS + int2(-1, 0));
                 float4 c4 = SampleInput(positionSS + int2(0, 0));
                 float4 c5 = SampleInput(positionSS + int2(+1, 0));

                 float4 c6 = SampleInput(positionSS + int2(-1, +1));
                 float4 c7 = SampleInput(positionSS + int2(0, +1));
                 float4 c8 = SampleInput(positionSS + int2(+1, +1));
    
                // return c4;

               half4 sharpenedcolor = (c4 - (c0 + c1 + c2 + c3 - 8 * c4 + c5 + c6 + c7 + c8) * _Sharpening)*thresholdEdge;

               return lerp(c4,c4+sharpenedcolor,_Smoothness);*/

            }
           ENDHLSL
        }
    }

    Fallback "Hidden/InternalErrorShader"
}                                                                                                                                                                                                                                                                   