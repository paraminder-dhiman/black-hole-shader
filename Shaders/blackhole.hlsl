// Black Hole · Custom node for M_BlackHole (1.1 hybrid)
// Raymarched black hole in the actor's local space · black hole at the origin · disk in the local XY plane
// Outputs: Color (rgb = disk light, a = disk opacity) · Dir (local direction the ray leaves in) · Mask (1 = ray escaped, show the sky)

#define SHADOWSTEPS 8
#define PI2 6.28318

struct BlackHoleProperties
{
    float Mass;                 // Mass of the black hole
    float EventHorizon;         // Event horizon radius, Mass * 2

    Texture2D DiskTexture;
    SamplerState DiskTextureSampler;
    float DiskDensity;
    float DiskDensityBias;
    float DiskOuterRadius;
    float DiskInnerRadius;

    float FogDensity;
    float FogHeight;
    float FogExponent;

    float3 LightColor;
    float LightIntensity;
    float LightBias;

    float DopplerIntensity;     // 0 = off · 1 = physical orbital speed
    float DopplerExponent;      // brightness ~ shift ^ exponent
    float PhysicalColor;        // 0 = colour curve · 1 = blackbody colour
    float InnerTemperature;     // kelvin at the inner edge

    float3 ShadowColor;
    float ShadowDensity;
    float ShadowStepSize;
    float ShadowSpread;

    float OrbitalBandSize;
    float AnimationScale;
    float AnimExponent;

    float StepScale;
    float VolumeStep;
    float MaxSteps;
    float Jitter;

    Texture2D AtlasTexture;
    SamplerState AtlasTextureSampler;
};

struct Functions
{
    // ---------------- light bending ----------------

    // Schwarzschild light bending in this form: a = -3M |p x v|^2 p / r^5
    float3 Acceleration(float3 P, float3 V, BlackHoleProperties BHP)
    {
        float3 C = cross(P, V);
        float R2 = dot(P, P);
        return (-3.0 * BHP.Mass * dot(C, C) / (R2 * R2 * sqrt(R2))) * P;
    }

    // Leapfrog step: half a bend, a move, another half bend
    void StepRay(inout float3 RayPos, inout float3 RayDir, float StepSize, BlackHoleProperties BHP)
    {
        RayDir += Acceleration(RayPos, RayDir, BHP) * (StepSize * 0.5);
        RayPos += RayDir * StepSize;
        RayDir += Acceleration(RayPos, RayDir, BHP) * (StepSize * 0.5);
        RayDir = normalize(RayDir);
    }

    // Fixed step inside the disk volume · grows with distance outside it, without jumping past the volume
    float GetStepSize(float3 RayPos, BlackHoleProperties BHP)
    {
        float R = length(RayPos);
        float Rho = length(RayPos.xy);
        float DZ = abs(RayPos.z) - BHP.FogHeight;
        float DR = max(BHP.DiskInnerRadius - Rho, Rho - BHP.DiskOuterRadius);

        if (DZ < 0.0 && DR < 0.0)
        {
            return BHP.VolumeStep;
        }

        float DistToVolume = (DZ > 0.0 && DR > 0.0) ? length(float2(DZ, DR)) : max(DZ, DR);
        float Scale = (R < 2.0 * BHP.DiskOuterRadius) ? BHP.StepScale : 0.5;
        return min(Scale * R, max(DistToVolume, 0.25 * BHP.VolumeStep));
    }

    // ---------------- disk volume ----------------

    float DiskMask(float3 RayPos, BlackHoleProperties BHP)
    {
        float Distance = length(RayPos);
        float OuterMask = 1.0 - Distance / BHP.DiskOuterRadius;
        float InnerMaskFallOff = 1.0 + Distance / BHP.DiskInnerRadius;
        float InnerMask = saturate((Distance - BHP.DiskInnerRadius) * InnerMaskFallOff);
        return OuterMask * InnerMask;
    }

    bool InFogVolume(float3 RayPos, BlackHoleProperties BHP)
    {
        float Dist = length(RayPos.xy);
        return (Dist > BHP.DiskInnerRadius && Dist < BHP.DiskOuterRadius && abs(RayPos.z) < BHP.FogHeight);
    }

    float SampleFogDensity(float3 RayPos, BlackHoleProperties BHP)
    {
        float f = 1.0 - (abs(RayPos.z) / BHP.FogHeight);
        f = max(0.0, pow(max(f, 0.0), BHP.FogExponent) * BHP.FogDensity);
        return f * DiskMask(RayPos, BHP);
    }

    float CalculateLighting(float3 RayPos, BlackHoleProperties BHP)
    {
        float Distance = max(0.0, length(RayPos) - BHP.LightBias);
        return min(1.0 / max(Distance * Distance, 1e-12), 1000.0);
    }

    float DensityAttenuation(float3 RayPos, BlackHoleProperties BHP)
    {
        float f = 1.0 - (abs(RayPos.z) / BHP.FogHeight);
        return 1.0 - saturate(pow(max(f, 0.0), BHP.FogExponent * 2.0));
    }

    float RemapValueRange(float Input, float InputLow, float InputHigh, float TargetLow, float TargetHigh)
    {
        float Result = (Input - InputLow) / (InputHigh - InputLow);
        Result *= TargetHigh - TargetLow;
        Result += TargetLow;
        return clamp(Result, TargetLow, TargetHigh);
    }

    float2 RotateUV(float2 UV, float2 Pivot, float Speed)
    {
        float Time = View.GameTime * Speed;
        float2x2 Rot = { cos(Time), -sin(Time),
                         sin(Time),  cos(Time) };
        UV = mul(UV + Pivot, Rot);
        return UV - Pivot;
    }

    // Disk texture in orbital bands · returns colour-curve colour (rgb) and density (a)
    float4 SampleDisk(float3 RayPosition, float MipLevel, BlackHoleProperties BHP)
    {
        float Distance = length(RayPosition);
        float OrbitalBands = BHP.DiskOuterRadius / BHP.OrbitalBandSize;

        float Radius = max(0.0, Distance - BHP.EventHorizon);
        float RadiusOffset = Radius + BHP.OrbitalBandSize * 0.5;

        float Bands = ceil(Radius / BHP.OrbitalBandSize) / OrbitalBands;
        float BandsOffset = ceil(RadiusOffset / BHP.OrbitalBandSize) / OrbitalBands - 0.5 / OrbitalBands;

        float OrbitalVelocity = sqrt(BHP.Mass / max(pow(Bands, BHP.AnimExponent), 1e-12));
        float OrbitalVelocityOffset = sqrt(BHP.Mass / max(pow(BandsOffset, BHP.AnimExponent), 1e-12));

        float2 UV = RayPosition.xy / (BHP.DiskOuterRadius * 2.0) - 0.5;
        float2 UV1 = RotateUV(UV, float2(0.5, 0.5), OrbitalVelocity * BHP.AnimationScale);
        float2 UV2 = RotateUV(UV, float2(0.5, 0.5), OrbitalVelocityOffset * BHP.AnimationScale);

        float4 DiskSample1 = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV1, MipLevel);
        float4 DiskSample2 = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV2, MipLevel);

        float BandMask = sin((Radius / BHP.OrbitalBandSize - 0.25) * PI2) * 0.5 + 0.5;
        float Disk = lerp(DiskSample2.x, DiskSample1.x, BandMask);

        float AtlasUV = RemapValueRange(Distance, BHP.DiskInnerRadius, BHP.DiskOuterRadius, 0.0, 1.0);
        AtlasUV += (Disk - 0.5) * 0.5;
        float4 DiskColor = BHP.AtlasTexture.SampleLevel(BHP.AtlasTextureSampler, float2(saturate(AtlasUV), 0.5), 0);

        float Attenuation = DensityAttenuation(RayPosition, BHP);
        float Bias = max(BHP.DiskDensityBias, 1.0 - DiskColor.w);

        float Density = saturate(Disk - Bias) / (1.0 - Bias);
        Density = max(0.0, Density - Attenuation) / max(1.0 - Attenuation, 0.000001);
        Density *= BHP.DiskDensity * DiskMask(RayPosition, BHP);

        return float4(DiskColor.xyz, Density);
    }

    // Cheap density for shadow rays: one band, one read, no colour
    float SampleShadowDensity(float3 RayPosition, float MipLevel, BlackHoleProperties BHP)
    {
        float OrbitalBands = BHP.DiskOuterRadius / BHP.OrbitalBandSize;
        float Radius = max(0.0, length(RayPosition) - BHP.EventHorizon);
        float Bands = ceil(Radius / BHP.OrbitalBandSize) / OrbitalBands;
        float OrbitalVelocity = sqrt(BHP.Mass / max(pow(Bands, BHP.AnimExponent), 1e-12));

        float2 UV = RayPosition.xy / (BHP.DiskOuterRadius * 2.0) - 0.5;
        UV = RotateUV(UV, float2(0.5, 0.5), OrbitalVelocity * BHP.AnimationScale);
        float Disk = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV, MipLevel).x;

        float Attenuation = DensityAttenuation(RayPosition, BHP);
        float Density = saturate(Disk - BHP.DiskDensityBias) / (1.0 - BHP.DiskDensityBias);
        Density = max(0.0, Density - Attenuation) / max(1.0 - Attenuation, 0.000001);
        return Density * BHP.DiskDensity * DiskMask(RayPosition, BHP);
    }

    // ---------------- physics on top ----------------

    // Doppler + gravitational shift for gas orbiting at radius R, seen along RayDir
    float DopplerFactor(float3 RayPos, float3 RayDir, BlackHoleProperties BHP)
    {
        float R = length(RayPos);
        float Spin = BHP.AnimationScale >= 0.0 ? 1.0 : -1.0;
        float2 Tangent = float2(-RayPos.y, RayPos.x) / length(RayPos.xy) * Spin;
        float Beta = min(BHP.DopplerIntensity * sqrt(BHP.Mass / max(R - 2.0 * BHP.Mass, 0.001)), 0.99);
        float Gamma = 1.0 / sqrt(1.0 - Beta * Beta);
        float Doppler = 1.0 / (Gamma * (1.0 + Beta * dot(Tangent, RayDir.xy)));
        float Gravity = sqrt(max(1.0 - 2.0 * BHP.Mass / R, 0.0));
        return Doppler * lerp(1.0, Gravity, BHP.DopplerIntensity);
    }

    // Colour of a body glowing at a temperature (kelvin), brightness 1
    float3 Blackbody(float Temperature)
    {
        float T = clamp(Temperature, 1000.0, 15000.0);
        float U = (0.860117757 + 1.54118254e-4 * T + 1.28641212e-7 * T * T) / (1.0 + 8.42420235e-4 * T + 7.08145163e-7 * T * T);
        float V = (0.317398726 + 4.22806245e-5 * T + 4.20481691e-8 * T * T) / (1.0 - 2.89741816e-5 * T + 1.61456053e-7 * T * T);
        float X = 3.0 * U / (2.0 * U - 8.0 * V + 4.0);
        float Y = 2.0 * V / (2.0 * U - 8.0 * V + 4.0);
        float3 XYZ = float3(X / Y, 1.0, (1.0 - X - Y) / Y);
        float3 RGB = float3(
             3.2404542 * XYZ.x - 1.5371385 * XYZ.y - 0.4985314 * XYZ.z,
            -0.9692660 * XYZ.x + 1.8760108 * XYZ.y + 0.0415560 * XYZ.z,
             0.0556434 * XYZ.x - 0.2040259 * XYZ.y + 1.0572252 * XYZ.z);
        return max(RGB, 0.0);
    }

    // ---------------- the raymarch ----------------

    void BlackHole(inout float4 Color, inout float Mask, inout float3 Dir, float3 CameraPosition, float Random, BlackHoleProperties BHP)
    {
        float3 RayPos = CameraPosition;
        float3 RayDir = Dir;

        float Transmittance = 1.0;
        float3 RayColor = 0.0;
        float3 Luma = float3(0.2126, 0.7152, 0.0722);

        float EscapeRadius = 20.0 * BHP.DiskOuterRadius;
        bool Captured = true;

        [loop]
        for (int i = 0; i < (int)BHP.MaxSteps; i++)
        {
            float R = length(RayPos);
            if (R <= BHP.EventHorizon)
            {
                break;
            }
            if (R > EscapeRadius && dot(RayPos, RayDir) > 0.0)
            {
                Captured = false;
                break;
            }

            float StepSize = GetStepSize(RayPos, BHP);
            float3 StepStart = RayPos;
            StepRay(RayPos, RayDir, StepSize, BHP);

            // Sample at a jittered point along this step · the light path itself never changes between frames
            float3 SamplePos = lerp(StepStart, RayPos, 1.0 - BHP.Jitter + BHP.Jitter * Random);

            if (InFogVolume(SamplePos, BHP))
            {
                float FogSample = SampleFogDensity(SamplePos, BHP);
                float4 DiskSample = SampleDisk(SamplePos, 0.0, BHP);
                float Density = FogSample + DiskSample.w;

                if (Density > 0.00001)
                {
                    float Dist = length(SamplePos);

                    // Fog colour straight from the colour curve by radius
                    float FogUV = RemapValueRange(Dist, BHP.DiskInnerRadius, BHP.DiskOuterRadius, 0.0, 1.0);
                    float3 FogColor = BHP.AtlasTexture.SampleLevel(BHP.AtlasTextureSampler, float2(FogUV, 0.5), 0).xyz;

                    // Doppler + redshift, temperature and colour
                    float Light = CalculateLighting(SamplePos, BHP) * BHP.LightIntensity;
                    float G = DopplerFactor(SamplePos, RayDir, BHP);
                    float Brightness = pow(G, BHP.DopplerExponent);
                    float Temperature = BHP.InnerTemperature * pow(BHP.DiskInnerRadius / Dist, 0.75) * G;
                    float3 BlackbodyColor = Blackbody(Temperature);

                    float3 DiskTint = DiskSample.xyz * BHP.LightColor;
                    float3 FogTint = FogColor * BHP.LightColor;
                    DiskTint = lerp(DiskTint, BlackbodyColor * dot(DiskTint, Luma), BHP.PhysicalColor);
                    FogTint = lerp(FogTint, BlackbodyColor * dot(FogTint, Luma), BHP.PhysicalColor);

                    // Shadow ray toward the centre
                    float3 LightingPos = SamplePos;
                    float3 LightDir = -SamplePos / Dist;
                    float ShadowAccumulation = 0.0;
                    for (int j = 0; j < SHADOWSTEPS; j++)
                    {
                        if (!InFogVolume(LightingPos, BHP))
                        {
                            break;
                        }
                        ShadowAccumulation += SampleFogDensity(LightingPos, BHP) + SampleShadowDensity(LightingPos, j * BHP.ShadowSpread, BHP);
                        LightingPos += LightDir * BHP.ShadowStepSize;
                    }
                    float3 Absorption = exp(-ShadowAccumulation * BHP.ShadowDensity * BHP.ShadowColor);

                    // Beer-Lambert over this step · fog and disk each use their own density
                    float StepTransmittance = exp(-Density * StepSize);
                    float Weight = Transmittance * (1.0 - StepTransmittance) / Density;
                    float3 Emission = FogTint * FogSample + DiskTint * DiskSample.w;
                    RayColor += Light * Brightness * Emission * Absorption * Weight;

                    Transmittance *= StepTransmittance;
                    if (Transmittance < 0.01)
                    {
                        break;
                    }
                }
            }
        }

        Mask = Captured ? 0.0 : 1.0;
        Color = float4(RayColor, 1.0 - Transmittance);
        Dir = RayDir;
    }
};

// ======================== main ========================

// Camera position and view direction in the actor's local space (transformed by engine nodes in the graph)
float3 CameraPositionLS = CameraPositionLocal;
float3 CameraDirectionLS = -normalize(CameraVectorLocal);

BlackHoleProperties BHP;
BHP.Mass = Mass;
BHP.EventHorizon = Mass * 2.0;
BHP.DiskTexture = DiskTexture;
BHP.DiskTextureSampler = DiskTextureSampler;
BHP.DiskDensity = DiskDensity;
BHP.DiskDensityBias = DiskDensityBias;
BHP.DiskOuterRadius = DiskOuterRadius;
BHP.DiskInnerRadius = DiskInnerRadius;
BHP.FogDensity = FogDensity;
BHP.FogHeight = FogHeight;
BHP.FogExponent = FogExponent;
BHP.LightColor = LightColor;
BHP.LightIntensity = LightIntensity;
BHP.LightBias = LightBias;
BHP.DopplerIntensity = DopplerIntensity;
BHP.DopplerExponent = DopplerExponent;
BHP.PhysicalColor = PhysicalColor;
BHP.InnerTemperature = InnerTemperature;
BHP.ShadowColor = ShadowColor;
BHP.ShadowDensity = ShadowDensity;
BHP.ShadowStepSize = ShadowStepSize;
BHP.ShadowSpread = ShadowSpread;
BHP.OrbitalBandSize = OrbitalBandSize;
BHP.AnimationScale = AnimationScale;
BHP.AnimExponent = AnimExponent;
BHP.StepScale = StepScale;
BHP.VolumeStep = VolumeStep;
BHP.MaxSteps = MaxSteps;
BHP.Jitter = JitterAmount;
BHP.AtlasTexture = AtlasTexture;
BHP.AtlasTextureSampler = AtlasTextureSampler;

int3 RandPos = int3(Parameters.SvPosition.xy, View.StateFrameIndexMod8);
float Random = float(Rand3DPCG16(RandPos).x) / 65535.0;

Color = 0.0;
Mask = 1.0;
Dir = CameraDirectionLS;

Functions FinalRender;
FinalRender.BlackHole(Color, Mask, Dir, CameraPositionLS, Random, BHP);

return 1.0;
