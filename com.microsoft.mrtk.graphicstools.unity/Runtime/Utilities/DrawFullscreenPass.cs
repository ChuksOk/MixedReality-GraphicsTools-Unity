// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#if GT_USE_URP
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Microsoft.MixedReality.GraphicsTools
{
    /// <summary>
    /// Draws full screen mesh using given material and pass and reading from source target.
    /// Forked from: https://github.com/Unity-Technologies/UniversalRenderingExamples/tree/master/Assets/Scripts/Runtime/RenderPasses
    /// </summary>
    internal class DrawFullscreenPass : ScriptableRenderPass
    {
        public FilterMode filterMode { get; set; }
        public DrawFullscreenFeature.Settings settings;

        private RenderTargetIdentifier source;
        private RenderTargetIdentifier destination;
        private RenderTargetIdentifier cameraColorTarget;
        private int temporaryRTId = Shader.PropertyToID("_TempRT");

        private int sourceId;
        private int destinationId;
        private bool isSourceAndDestinationSameTarget;
        private string profilerTag;

        public DrawFullscreenPass(string tag)
        {
            profilerTag = tag;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor blitTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            blitTargetDescriptor.depthBufferBits = 0;

            isSourceAndDestinationSameTarget = settings.sourceType == settings.destinationType &&
                (settings.sourceType == BufferType.CameraColor || settings.sourceTextureId == settings.destinationTextureId);

            var renderer = renderingData.cameraData.renderer;

            if (settings.sourceType == BufferType.CameraColor)
            {
                sourceId = -1;
                source = renderer.cameraColorTarget;
            }
            else
            {
                sourceId = Shader.PropertyToID(settings.sourceTextureId);
                cmd.GetTemporaryRT(sourceId, blitTargetDescriptor, filterMode);
                source = new RenderTargetIdentifier(sourceId);
            }

            if (isSourceAndDestinationSameTarget)
            {
                destinationId = temporaryRTId;
                cmd.GetTemporaryRT(destinationId, blitTargetDescriptor, filterMode);
                destination = new RenderTargetIdentifier(destinationId);
            }
            else if (settings.destinationType == BufferType.CameraColor)
            {
                destinationId = -1;
                destination = renderer.cameraColorTarget;
            }
            else
            {
                destinationId = Shader.PropertyToID(settings.destinationTextureId);
                cmd.GetTemporaryRT(destinationId, blitTargetDescriptor, filterMode);
                destination = new RenderTargetIdentifier(destinationId);
            }

            cameraColorTarget = renderer.cameraColorTarget;
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(profilerTag);

            bool isXR = renderingData.cameraData.xrRendering;

            // Can't read and write to same color target, create a temp render target to blit.
            if (isSourceAndDestinationSameTarget)
            {
                Blit(cmd, source, destination, settings.blitMaterial, settings.blitMaterialPassIndex, isXR);
                Blit(cmd, destination, source, settings.blitMaterial, 0, isXR);
            }
            else
            {
                Blit(cmd, source, destination, settings.blitMaterial, settings.blitMaterialPassIndex, isXR);
            }

            if (settings.restoreCameraColorTarget)
            {
                cmd.SetRenderTarget(cameraColorTarget);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        /// <inheritdoc/>
        public override void FrameCleanup(CommandBuffer cmd)
        {
            if (destinationId != -1)
                cmd.ReleaseTemporaryRT(destinationId);

            if (source == destination && sourceId != -1)
                cmd.ReleaseTemporaryRT(sourceId);
        }

        // URP Blit() doesn't currently work with multiview.
        private void Blit(CommandBuffer cmd, RenderTargetIdentifier source, RenderTargetIdentifier target, Material material, int pass, bool isXR)
        {
            if (isXR)
            {
                Vector4 scaleBias = new Vector4(1, 1, 0, 0);
                Vector4 scaleBiasRt = new Vector4(1, 1, 0, 0);
                cmd.SetGlobalVector("_ScaleBias", scaleBias);
                cmd.SetGlobalVector("_ScaleBiasRt", scaleBiasRt);
                cmd.SetRenderTarget(target);
                cmd.DrawProcedural(Matrix4x4.identity, material, pass, MeshTopology.Quads, 4, 1, null);
            }
            else
            {
                cmd.SetRenderTarget(target);
                cmd.Blit(source, BuiltinRenderTextureType.CurrentActive, material, pass);
            }
        }
    }
}
#endif // GT_USE_URP
