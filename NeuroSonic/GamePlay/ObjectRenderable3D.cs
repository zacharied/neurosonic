﻿using System.Diagnostics;
using System.Numerics;

using theori;
using theori.Charting;
using theori.Graphics;
using theori.Resources;

using NeuroSonic.Charting;
using System;

namespace NeuroSonic.GamePlay
{
    internal sealed class ObjectRenderable3DStaticResources : System.Disposable
    {
        public readonly Mesh ButtonChipLeftMesh, ButtonChipRightMesh;
        public readonly Mesh ButtonHoldLeftMesh, ButtonHoldRightMesh;

        public ObjectRenderable3DStaticResources()
        {
            ButtonChipLeftMesh = Mesh.CreatePlane(Vector3.UnitX, Vector3.UnitZ, 1.0f / 12, 0.1f, Anchor.BottomRight, new Rect(0, 0, 0.5f, 1));
            ButtonChipRightMesh = Mesh.CreatePlane(Vector3.UnitX, Vector3.UnitZ, 1.0f / 12, 0.1f, Anchor.BottomLeft, new Rect(0.5f, 0, 0.5f, 1));

            ButtonHoldLeftMesh = Mesh.CreatePlane(Vector3.UnitX, Vector3.UnitZ, 1.0f / 12, 1.0f, Anchor.BottomRight, new Rect(0, 0, 0.5f, 1));
            ButtonHoldRightMesh = Mesh.CreatePlane(Vector3.UnitX, Vector3.UnitZ, 1.0f / 12, 1.0f, Anchor.BottomLeft, new Rect(0.5f, 0, 0.5f, 1));
        }

        protected override void DisposeManaged()
        {
            ButtonChipLeftMesh.Dispose();
            ButtonHoldLeftMesh.Dispose();
        }
    }

    internal abstract class ObjectRenderable3D : System.Disposable
    {
        public readonly Entity Object;

        protected ObjectRenderable3D(Entity obj)
        {
            Object = obj;
        }

        public abstract void Render(RenderQueue rq, Transform world, float len);
    }

    internal abstract class GlowingRenderState3D : ObjectRenderable3D
    {
        private float m_glow = -1.0f;
        private int m_glowState = -1;

        protected GlowingRenderState3D(Entity obj)
            : base(obj)
        {
        }

        public float Glow
        {
            get => m_glow;
            set => SetGlow(m_glow = value);
        }
        public int GlowState
        {
            get => m_glowState;
            set => SetGlowState(m_glowState = value);
        }

        protected abstract void SetGlow(float glow);
        protected abstract void SetGlowState(int glow);
    }

    public interface IButtonRenderState3D
    {
        public int SplitDrawMode { get; set; }
    }

    internal class ButtonChipRenderState3D : ObjectRenderable3D, IButtonRenderState3D
    {
        public new ButtonEntity Object => (ButtonEntity)base.Object;

        private readonly int m_width;

        private readonly Drawable3D[] m_drawables;

        public int SplitDrawMode { get; set; } = 0;

        public ButtonChipRenderState3D(ButtonEntity obj, ClientResourceManager resources, ObjectRenderable3DStaticResources staticResources)
            : base(obj)
        {
            Debug.Assert(obj.IsChip, "Hold object passed to render state which expects a chip");

            string textureName;
            if ((int)obj.Lane < 4)
            {
                m_width = 1;
                if (obj.HasSample)
                    textureName = "textures/game/bt_chip_sample";
                else textureName = "textures/game/bt_chip";
            }
            else
            {
                m_width = 2;
                if (obj.HasSample)
                    textureName = "textures/game/fx_chip_sample";
                else textureName = "textures/game/fx_chip";
            }

            m_drawables = new[]
            {
                new Drawable3D()
                {
                    Texture = resources.GetTexture(textureName),
                    Material = resources.GetMaterial("materials/chip"),
                    Mesh = staticResources.ButtonChipLeftMesh,
                },
                new Drawable3D()
                {
                    Texture = resources.GetTexture(textureName),
                    Material = resources.GetMaterial("materials/chip"),
                    Mesh = staticResources.ButtonChipRightMesh,
                }
            };
        }

        public override void Render(RenderQueue rq, Transform world, float len)
        {
            if (SplitDrawMode == 0)
            {
                foreach (var d in m_drawables)
                    d.DrawToQueue(rq, Transform.Scale(m_width, 1, len) * world);
            }
            else m_drawables[SplitDrawMode - 1].DrawToQueue(rq, Transform.Scale(m_width, 1, len) * world);
        }
    }

    internal class ButtonHoldRenderState3D : GlowingRenderState3D, IButtonRenderState3D
    {
        private const float ENTRY_LENGTH = 0.15f;
        private const float EXIT_LENGTH = ENTRY_LENGTH;

        public new ButtonEntity Object => (ButtonEntity)base.Object;

        private readonly int m_width;

        private readonly Drawable3D[] m_drawables;

        public int SplitDrawMode { get; set; } = 0;

        public ButtonHoldRenderState3D(ButtonEntity obj, ClientResourceManager resources, ObjectRenderable3DStaticResources staticResources)
            : base(obj)
        {
            Debug.Assert(obj.IsHold, "Chip object passed to render state which expects a hold");

            string holdTextureName;
            if ((int)obj.Lane < 4)
            {
                holdTextureName = "textures/game/bt_hold";
                m_width = 1;
            }
            else
            {
                holdTextureName = "textures/game/fx_hold";
                m_width = 2;
            }

            m_drawables = new[]
            {
                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName),
                    Material = resources.GetMaterial("materials/hold"),
                    Mesh = staticResources.ButtonHoldLeftMesh,
                },
                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName),
                    Material = resources.GetMaterial("materials/hold"),
                    Mesh = staticResources.ButtonHoldRightMesh,
                },

                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName + "_entry"),
                    Material = resources.GetMaterial("materials/basic"),
                    Mesh = staticResources.ButtonHoldLeftMesh,
                },
                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName + "_entry"),
                    Material = resources.GetMaterial("materials/basic"),
                    Mesh = staticResources.ButtonHoldRightMesh,
                },

                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName + "_exit"),
                    Material = resources.GetMaterial("materials/hold"),
                    Mesh = staticResources.ButtonHoldLeftMesh,
                },
                new Drawable3D()
                {
                    Texture = resources.GetTexture(holdTextureName + "_exit"),
                    Material = resources.GetMaterial("materials/hold"),
                    Mesh = staticResources.ButtonHoldRightMesh,
                },
            };

            foreach (var d in m_drawables)
                d.Params["Color"] = Vector4.One;

            Glow = 0.0f;
            GlowState = 1;
        }

        protected override void SetGlow(float glow)
        {
            foreach (var d in m_drawables)
                d.Params["GlowState"] = glow;
        }

        protected override void SetGlowState(int glowState)
        {
            foreach (var d in m_drawables)
                d.Params["GlowState"] = glowState;
        }

        public override void Render(RenderQueue rq, Transform world, float len)
        {
            var holdTransform = Transform.Scale(m_width, 1, len - EXIT_LENGTH - ENTRY_LENGTH) * Transform.Translation(0, 0, -ENTRY_LENGTH);
            var entryTransform = Transform.Scale(m_width, 1, ENTRY_LENGTH);
            var exitTransform = Transform.Scale(m_width, 1, EXIT_LENGTH) * Transform.Translation(0, 0, -len + EXIT_LENGTH);

            if (SplitDrawMode == 0)
            {
                m_drawables[0].DrawToQueue(rq, holdTransform * world);
                m_drawables[1].DrawToQueue(rq, holdTransform * world);

                m_drawables[2].DrawToQueue(rq, entryTransform * world);
                m_drawables[3].DrawToQueue(rq, entryTransform * world);

                m_drawables[4].DrawToQueue(rq, exitTransform * world);
                m_drawables[5].DrawToQueue(rq, exitTransform * world);
            }
            else
            {
                int offs = SplitDrawMode - 1;
                m_drawables[0 + offs].DrawToQueue(rq, holdTransform * world);
                m_drawables[2 + offs].DrawToQueue(rq, entryTransform * world);
                m_drawables[4 + offs].DrawToQueue(rq, exitTransform * world);
            }
        }
    }

    internal class SlamRenderState3D : GlowingRenderState3D
    {
        private const float LASER_WIDTH = 2.0f;

        public new AnalogEntity Object => (AnalogEntity)base.Object;
        
        private readonly Drawable3D m_drawable;

        public SlamRenderState3D(AnalogEntity obj, Vector3 color, ClientResourceManager skin)
            : base(obj)
        {
            Debug.Assert(obj.IsInstant, "Analog for slam render state wasn't a slam");
            
            float range = 5 / 6.0f * (obj.RangeExtended ? 2 : 1);
            
            var mesh = new Mesh();

            const float W = LASER_WIDTH / 6.0f;

            float il  = range * (obj.InitialValue - 0.5f) - W / 2;
            float ilh = range * (obj.InitialValue - 0.5f) - W / 4;
            float ir  = range * (obj.InitialValue - 0.5f) + W / 2;
            float irh = range * (obj.InitialValue - 0.5f) + W / 4;

            float fl  = range * (obj.FinalValue - 0.5f) - W / 2;
            float flh = range * (obj.FinalValue - 0.5f) - W / 4;
            float fr  = range * (obj.FinalValue - 0.5f) + W / 2;
            float frh = range * (obj.FinalValue - 0.5f) + W / 4;

            if (obj.InitialValue < obj.FinalValue)
            {

#if false
                ushort[] indices = new ushort[] { 0, 1, 2, 1, 5, 2, 2, 5, 4, 3, 4, 5 };
                VertexP3T2[] vertices = new VertexP3T2[6]
                {
                    new VertexP3T2(new Vector3(il, 0, 0), new Vector2(0, 1)),
                    new VertexP3T2(new Vector3(il, 0, -1), new Vector2(0, 0)),
                    new VertexP3T2(new Vector3(ir, 0, 0), new Vector2(1, 1)),

                    new VertexP3T2(new Vector3(fr, 0, -1), new Vector2(1, 0)),
                    new VertexP3T2(new Vector3(fr, 0, 0), new Vector2(1, 1)),
                    new VertexP3T2(new Vector3(fl, 0, -1), new Vector2(0, 1)),
                };
#else
                ushort[] indices = new ushort[] { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
                VertexP3T2[] vertices = new VertexP3T2[]
                {
                    new VertexP3T2(new Vector3(il , 0,  0.0f), new Vector2(0.00f, 0.875f)),
                    new VertexP3T2(new Vector3(il , 0, -1.5f), new Vector2(0.00f, 0.500f)),
                    new VertexP3T2(new Vector3(irh, 0,  0.0f), new Vector2(0.75f, 0.875f)),

                    new VertexP3T2(new Vector3(ir , 0,  0.5f), new Vector2(1.00f, 0.000f)),
                    new VertexP3T2(new Vector3(il , 0, -1.5f), new Vector2(0.00f, 0.500f)),
                    new VertexP3T2(new Vector3(fl , 0, -1.5f), new Vector2(0.00f, 0.000f)),

                    new VertexP3T2(new Vector3(ir , 0,  0.5f), new Vector2(1.00f, 1.000f)),
                    new VertexP3T2(new Vector3(fl , 0, -1.5f), new Vector2(0.00f, 0.000f)),
                    new VertexP3T2(new Vector3(fr , 0,  0.5f), new Vector2(1.00f, 1.000f)),

                    new VertexP3T2(new Vector3(fr , 0,  0.5f), new Vector2(1.00f, 0.500f)),
                    new VertexP3T2(new Vector3(flh, 0, -1.0f), new Vector2(0.25f, 0.125f)),
                    new VertexP3T2(new Vector3(fr , 0, -1.0f), new Vector2(1.00f, 0.125f)),
                };
#endif

                mesh.SetIndices(indices);
                mesh.SetVertices(vertices);
            }
            else
            {
#if false
                ushort[] indices = new ushort[] { 0, 1, 2, 4, 1, 0, 4, 0, 5, 3, 4, 5 };
                VertexP3T2[] vertices = new VertexP3T2[6]
                {
                    new VertexP3T2(new Vector3(il, 0, 0), new Vector2(0, 1)),
                    new VertexP3T2(new Vector3(ir, 0, -1), new Vector2(1, 0)),
                    new VertexP3T2(new Vector3(ir, 0, 0), new Vector2(1, 1)),

                    new VertexP3T2(new Vector3(fl, 0, -1), new Vector2(0, 0)),
                    new VertexP3T2(new Vector3(fr, 0, -1), new Vector2(1, 0)),
                    new VertexP3T2(new Vector3(fl, 0, 0), new Vector2(0, 1)),
                };
#else
                ushort[] indices = new ushort[] { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
                VertexP3T2[] vertices = new VertexP3T2[]
                {
                    new VertexP3T2(new Vector3(ilh, 0,  0.0f), new Vector2(0.25f, 0.875f)),
                    new VertexP3T2(new Vector3(ir , 0, -1.5f), new Vector2(1.00f, 0.500f)),
                    new VertexP3T2(new Vector3(ir , 0,  0.0f), new Vector2(1.00f, 0.875f)),


                    new VertexP3T2(new Vector3(il , 0,  0.5f), new Vector2(0.00f, 1.000f)),
                    new VertexP3T2(new Vector3(fr , 0, -1.5f), new Vector2(1.00f, 0.000f)),
                    new VertexP3T2(new Vector3(ir , 0, -1.5f), new Vector2(1.00f, 1.000f)),

                    new VertexP3T2(new Vector3(il , 0,  0.5f), new Vector2(0.00f, 1.000f)),
                    new VertexP3T2(new Vector3(fl , 0,  0.5f), new Vector2(0.00f, 0.000f)),
                    new VertexP3T2(new Vector3(fr , 0, -1.5f), new Vector2(1.00f, 0.000f)),


                    new VertexP3T2(new Vector3(fl , 0,  0.5f), new Vector2(0.00f, 0.500f)),
                    new VertexP3T2(new Vector3(fl , 0, -1.0f), new Vector2(0.00f, 0.125f)),
                    new VertexP3T2(new Vector3(frh, 0, -1.0f), new Vector2(0.75f, 0.125f)),
                };
#endif

                mesh.SetIndices(indices);
                mesh.SetVertices(vertices);
            }

            m_drawable = new Drawable3D()
            {
                Texture = skin.GetTexture("textures/game/laser"),
                Material = skin.GetMaterial("materials/laser"),
                Mesh = mesh,
            };

            m_drawable.Material.BlendMode = BlendMode.Additive;

            m_drawable.Params["LaserColor"] = color;
            m_drawable.Params["HiliteColor"] = new Vector3(1, 1, 0);

            Glow = 0.0f;
            GlowState = 1;
        }

        protected override void SetGlow(float glow)
        {
            m_drawable.Params["GlowState"] = glow;
        }

        protected override void SetGlowState(int glowState)
        {
            m_drawable.Params["GlowState"] = glowState;
        }

        protected override void DisposeManaged()
        {
            m_drawable.Mesh.Dispose();
        }

        public override void Render(RenderQueue rq, Transform world, float len)
        {
            m_drawable.DrawToQueue(rq, Transform.Scale(1, 1, len) * world);
        }
    }

    internal class LaserRenderState3D : GlowingRenderState3D
    {
        private const float LASER_WIDTH = 2.0f;
        private const float AUTO_RESOLUTION_AMT = 1.0f / 64;

        public new AnalogEntity Object => (AnalogEntity)base.Object;
        
        private readonly Drawable3D m_drawable;

        public LaserRenderState3D(AnalogEntity obj, Vector3 color, ClientResourceManager skin)
            : base(obj)
        {
            Debug.Assert(!obj.IsInstant, "analog for segment render state was a slam");

            var mesh = new Mesh();

            const float W = LASER_WIDTH / 6.0f;
            
            float range = 5 / 6.0f * (obj.RangeExtended ? 2 : 1);

            float il = range * (obj.InitialValue - 0.5f) - W / 2;
            float ir = range * (obj.InitialValue - 0.5f) + W / 2;
            
            float fl = range * (obj.FinalValue - 0.5f) - W / 2;
            float fr = range * (obj.FinalValue - 0.5f) + W / 2;

            VertexP3T2[] vertices;
            ushort[] indices;

            int SegmentCount()
            {
                //if (obj.CurveResolution > 0) return obj.CurveResolution;
                return MathL.Max(4, MathL.FloorToInt((float)obj.Duration / AUTO_RESOLUTION_AMT));
            }

            if (obj.Shape == CurveShape.Cosine || obj.Shape == CurveShape.ThreePoint)
            {
                int segments = SegmentCount();

                indices = new ushort[segments * 6];
                vertices = new VertexP3T2[(segments + 1) * 2];

                for (int i = 0; i < segments; i++)
                {
                    indices[i * 6 + 0] = (ushort)(i * 2 + 0);
                    indices[i * 6 + 1] = (ushort)(i * 2 + 3);
                    indices[i * 6 + 2] = (ushort)(i * 2 + 1);
                    indices[i * 6 + 3] = (ushort)(i * 2 + 0);
                    indices[i * 6 + 4] = (ushort)(i * 2 + 2);
                    indices[i * 6 + 5] = (ushort)(i * 2 + 3);
                }

                float fTex = 0.0f, fTexOffs = 1.0f / segments;
                for (int v = 0; v <= segments; v++, fTex += fTexOffs)
                {
                    int i = v * 2;

                    float alpha = (float)v / segments;
                    float xa = obj.Shape.Sample(alpha, obj.CurveA, obj.CurveB);
                    float xl = MathL.Lerp(il, fl, xa), xr = MathL.Lerp(ir, fr, xa);

                    vertices[i + 0] = new VertexP3T2(new Vector3(xl, 0, -alpha), new Vector2(0, -fTex));
                    vertices[i + 1] = new VertexP3T2(new Vector3(xr, 0, -alpha), new Vector2(1, -fTex));
                }
            }
            else
            {
                indices = new ushort[] { 0, 1, 2, 0, 2, 3, };
                vertices = new VertexP3T2[4]
                {
                    new VertexP3T2(new Vector3(il, 0, 0), new Vector2(0, 1)),
                    new VertexP3T2(new Vector3(fl, 0, -1), new Vector2(0, 0)),
                    new VertexP3T2(new Vector3(fr, 0, -1), new Vector2(1, 0)),
                    new VertexP3T2(new Vector3(ir, 0, 0), new Vector2(1, 1)),
                };
            }

            mesh.SetIndices(indices);
            mesh.SetVertices(vertices);

            m_drawable = new Drawable3D()
            {
                Texture = skin.GetTexture("textures/game/laser"),
                Material = skin.GetMaterial("materials/laser"),
                Mesh = mesh,
            };

            m_drawable.Material.BlendMode = BlendMode.Additive;

            m_drawable.Params["LaserColor"] = color;
            m_drawable.Params["HiliteColor"] = new Vector3(1, 1, 0);

            Glow = 0.0f;
            GlowState = 1;
        }

        protected override void SetGlow(float glow)
        {
            m_drawable.Params["GlowState"] = glow;
        }

        protected override void SetGlowState(int glowState)
        {
            m_drawable.Params["GlowState"] = glowState;
        }

        protected override void DisposeManaged()
        {
            m_drawable.Mesh.Dispose();
        }

        public override void Render(RenderQueue rq, Transform world, float len)
        {
            m_drawable.DrawToQueue(rq, Transform.Scale(1, 1, len) * world);
        }
    }
}
