#define SHADOWSTEPS 8
#define PI2 6.28318
#define SPEED_OF_LIGHT 299792458.0

struct BlackHoleProperties
{
    float Mass; //Mass of the Black Hole
    float EventHorizon; //Black Hole Radius, Mass * 2

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

    float DopplerIntensity;
    float DopplerBias;
    float DopplerExponent;

    float3 ShadowColor;
    float ShadowDensity;
    float ShadowStepSize;
    float ShadowSpread;

    float OrbitalBandSize;
    float AnimationScale;
    float AnimExponent;

    float3 BlackHolePos;
    float3 CameraPos;
    float3 CameraVector;

    float StepScale;
    float VolumeStep;
    float MaxSteps;
    float Jitter;
    

    Texture2D AtlasTexture;
    SamplerState AtlasTextureSampler;

    Texture2D DopplerTexture;
    SamplerState DopplerTextureSampler;
};

// Position of the Black Hole assumed to be at the origin
struct Functions
{
    bool CrossedEventHorizon(float3 RayPos, BlackHoleProperties BHP)
    {
        if(length(RayPos) <= BHP.EventHorizon)
        {
            return true;
        }

        return false;
    }
        
    float3 Acceleration(float3 P, float3 V, BlackHoleProperties BHP)
    {
        float3 C = cross(P, V);
        float R2 = dot(P, P);
        return (-3.0 * BHP.Mass * dot(C, C) / (R2 * R2 * sqrt(R2))) * P;
    }

    bool CrossedAccretionDisk(float3 RayStart, float3 RayEnd)
    {
        return (sign(RayStart.z) != sign(RayEnd.z));
    }

    float CalculateDoppler (float3 RayPos, float3 PrevPos, BlackHoleProperties BHP)
    {
        float AccIntercept = abs((RayPos.z) / BHP.CameraVector.z);
        float3 Intercept = float3(RayPos.x, RayPos.y, RayPos.z) + (BHP.CameraVector * AccIntercept);
        float InterceptLength = length(Intercept);
        float RayLength = length(RayPos) / (pow(BHP.DopplerIntensity, 10) * BHP.EventHorizon);
        float3 AccretionVector = float3(-Intercept.y, Intercept.x, 0.0) / sqrt (2.0 * (InterceptLength - 1.0)) / (InterceptLength * InterceptLength);
        float Gamma = 1.0 / (sqrt(1.0 - dot(AccretionVector, AccretionVector)));
        float DopplerFactor = max((1.0 - BHP.DopplerBias) / Gamma * (1.0 + dot(InterceptLength / RayLength, AccretionVector)), 0.1);

        return DopplerFactor;
    }

    void StepRay(inout float3 RayPos, inout float3 RayDir, float StepSize, BlackHoleProperties BHP)
    {
        RayDir += Acceleration(RayPos, RayDir, BHP) * (StepSize * 0.5);
        RayPos += RayDir * StepSize;
        RayDir += Acceleration(RayPos, RayDir, BHP) * (StepSize * 0.5);
        RayDir = normalize(RayDir);
    }

    float GetStepSize(float3 RayPos, float Random, inout bool FirstVolumeStep, BlackHoleProperties BHP)
    {
        float R = length(RayPos);
        float Rho = length(RayPos.xy);
        float DZ = abs(RayPos.z) - BHP.FogHeight;
        float DR = max(BHP.DiskInnerRadius - Rho, Rho - BHP.DiskOuterRadius);

        if (DZ < 0.0 && DR < 0.0)
        {
            float Step = BHP.VolumeStep;
            if (FirstVolumeStep)
            {
                Step *= 1.0 - BHP.Jitter + BHP.Jitter * Random;
                FirstVolumeStep = false;
            }
            return Step;
        }

        float DistToVolume = (DZ > 0.0 && DR > 0.0) ? length(float2(DZ, DR)) : max(DZ, DR);
        float Scale = (R < 2.0 * BHP.DiskOuterRadius) ? BHP.StepScale : 0.5;
        return min(Scale * R, max(DistToVolume, 0.25 * BHP.VolumeStep));
    }

    float DiskMask(float3 RayPos, BlackHoleProperties BHP)
    {
        float Distance = length(RayPos);

        float OuterMask = 1.0 - Distance / BHP.DiskOuterRadius;

        float InnerMaskFallOff = 1.0 + Distance / BHP.DiskInnerRadius;// 0.125;
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
        f = max(0.0, pow(f, BHP.FogExponent) * BHP.FogDensity);
        return f * DiskMask(RayPos, BHP);
    }

    float CalculateLighting(float3 RayPos, BlackHoleProperties BHP)
    {
        float distance = max(0.0, length(RayPos) - BHP.LightBias);
        float result = 1.0 / (distance * distance);
        float LightingCalculation = min(result, 1000);
        return LightingCalculation;
    }

    float DensityAttenuation(float3 RayPos, BlackHoleProperties BHP)
    {
        float f = 1.0 - (abs(RayPos.z) / BHP.FogHeight);
        float DensityAttenuationExponent = BHP.FogExponent * 2.0;
        return 1.0 - saturate(pow(f, DensityAttenuationExponent));
    }

    float RemapValueRange(float Input, float InputLow, float InputHigh, float TargetLow, float TargetHigh)
    {
        float result = (Input - InputLow) / (InputHigh - InputLow);
        result *= TargetHigh - TargetLow;
        result += TargetLow;

        return clamp(result, TargetLow, TargetHigh);
    }

    float2 RotateUV(float2 UV, float2 Pivot, float Speed)
    {
        float Time = View.GameTime * Speed;
        float2x2 rot = { cos(Time), -sin(Time), //row1
                        sin(Time), cos (Time)}; //row2

        UV = mul(UV + Pivot, rot);

        return UV - Pivot;
    }

    float2 GetZIntercept(float3 RayStart, float3 RayEnd)
    {
        float3 Dir = normalize(RayEnd - RayStart);
        float RayLength = length(RayEnd - RayStart);
        float ProjectionDist = abs(RayStart.z) * RayLength / (abs(RayStart.z) + abs(RayEnd.z));
        float3 Intercept = RayStart + Dir * ProjectionDist;

        return Intercept.xy;
    }

    float4 SampleDisk(float3 RayPosition, float MipLevel, BlackHoleProperties BHP)
    {
        float Distance = length(RayPosition);

        //Number of Orbital Bands
        float OrbitalBands = BHP.DiskOuterRadius / BHP.OrbitalBandSize;

        //Distances
        float Radius = max(0.0, length(RayPosition) - BHP.EventHorizon);
        float RadiusOffset = Radius + BHP.OrbitalBandSize * 0.5;

        //Bands
        float Bands = ceil(Radius / BHP.OrbitalBandSize) / OrbitalBands;
        float Bands_Offset = ceil(RadiusOffset / BHP.OrbitalBandSize) / OrbitalBands;
        Bands_Offset -= 0.5 / OrbitalBands;

        //Velocities
        float OrbitalVelocity = sqrt(BHP.Mass / pow(Bands, BHP.AnimExponent));
        float OrbitalVelocityOffset = sqrt(BHP.Mass / pow(Bands_Offset, BHP.AnimExponent));

        //UVs
        float2 UV = RayPosition.xy / (BHP.DiskOuterRadius * 2.0) - 0.5;
        float2 UV1 = RotateUV(UV, 0.5, OrbitalVelocity * BHP.AnimationScale);
        float2 UV2 = RotateUV(UV, 0.5, OrbitalVelocityOffset * BHP.AnimationScale);

        float4 DiskSample1 = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV1, MipLevel);
        float4 DiskSample2 = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV2, MipLevel);

        //Remap Radius for blend mask
        float RadiusRemap = (Radius / BHP.OrbitalBandSize - 0.25) * PI2;
        float BandMask = sin(RadiusRemap) * 0.5 + 0.5;

        float Disk  = lerp(DiskSample2.x, DiskSample1.x, BandMask);

        float AtlasUV = RemapValueRange(Distance, BHP.DiskInnerRadius, BHP.DiskOuterRadius, 0.0, 1.0);
        AtlasUV += (Disk - 0.5) * 0.5;

        float4 DiskColor = BHP.AtlasTexture.SampleLevel(BHP.AtlasTextureSampler, float2(AtlasUV, 0.5), 0);

        float Attenuation = DensityAttenuation(RayPosition, BHP);
        float Bias = max(BHP.DiskDensityBias, (1.0 - DiskColor.w));

        float Density = saturate(Disk - Bias);
        Density *= (1.0 / (1.0 - Bias));

        Density = max(0.0, Density - Attenuation);
        Density *= (1.0/ max(1.0 - Attenuation, 0.000001));

        Density *= BHP.DiskDensity * DiskMask(RayPosition, BHP);

        return float4(DiskColor.xyz, Density);
    }

    float SampleShadowDensity(float3 RayPosition, float MipLevel, BlackHoleProperties BHP)
    {
        float OrbitalBands = BHP.DiskOuterRadius / BHP.OrbitalBandSize;
        float Radius = max(0.0, length(RayPosition) - BHP.EventHorizon);
        float Bands = ceil(Radius / BHP.OrbitalBandSize) / OrbitalBands;
        float OrbitalVelocity = sqrt(BHP.Mass / pow(Bands, BHP.AnimExponent));

        float2 UV = RayPosition.xy / (BHP.DiskOuterRadius * 2.0) - 0.5;
        UV = RotateUV(UV, 0.5, OrbitalVelocity * BHP.AnimationScale);
        float Disk = BHP.DiskTexture.SampleLevel(BHP.DiskTextureSampler, UV, MipLevel).x;

        float Attenuation = DensityAttenuation(RayPosition, BHP);
        float Density = saturate(Disk - BHP.DiskDensityBias) / (1.0 - BHP.DiskDensityBias);
        Density = max(0.0, Density - Attenuation) / max(1.0 - Attenuation, 0.000001);
        return Density * BHP.DiskDensity * DiskMask(RayPosition, BHP);
    }

    void BlackHole(inout float4 Color, inout float Mask, inout float3 Dir, float3 CameraPosition, float Random, BlackHoleProperties BHP)
    {
        float3 RayPos = CameraPosition;
        float3 RayDir = Dir;

        float Transmittance = 1.0;
        
        float3 RayColor = 0.0;
        

        //Begin Raymarch
        
        float EscapeRadius = 20.0 * BHP.DiskOuterRadius;
        bool Captured = true;
        bool FirstVolumeStep = true;

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

            float StepSize = GetStepSize(RayPos, Random, FirstVolumeStep, BHP);
            StepRay(RayPos, RayDir, StepSize, BHP);

            if (InFogVolume(RayPos, BHP))
            {
                float FogSample = SampleFogDensity(RayPos, BHP);
                float4 DiskSample = SampleDisk(RayPos, 0, BHP);
                float Density = FogSample + DiskSample.w;

                if (Density > 0.00001)
                {
                    float Dist = length(RayPos);

                    float FogUV = RemapValueRange(Dist, BHP.DiskInnerRadius, BHP.DiskOuterRadius, 0.0, 1.0);
                    float3 FogColor = BHP.AtlasTexture.SampleLevel(BHP.AtlasTextureSampler, float2(FogUV, 0.5), 0).xyz;

                    float3 LightEnergy = CalculateLighting(RayPos, BHP) * BHP.LightColor * BHP.LightIntensity;

                    float3 LightingPos = RayPos;
                    float3 LightDir = -RayPos / Dist;
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

                    float StepTransmittance = exp(-Density * StepSize);
                    float Weight = Transmittance * (1.0 - StepTransmittance) / Density;
                    float3 Emission = FogColor * FogSample + DiskSample.xyz * DiskSample.w;
                    RayColor += LightEnergy * Emission * Absorption * Weight;

                    Transmittance *= StepTransmittance;
                    if (Transmittance < 0.01)
                    {
                        break;
                    }
                }
            }
        
        }

        Mask = Captured ? 0.0 :1.0;

        Color = float4(RayColor, 1.0 - Transmittance);
        Dir = RayDir;
    }

};

float3 CameraPositionWS = LWCToFloat(ResolvedView.WorldCameraOrigin);
float3 CameraVectorWS = -Parameters.CameraVector;

//World to Local Transform
FDFInverseMatrix WorldToLocal = DFFromTileOffset(GetWorldToInstance(Parameters));
float3 CameraPositionLS = DFMultiplyVector(LWCHackToFloat(ResolvedView.WorldCameraOrigin), WorldToLocal);
float3 CameraVectorLS = DFMultiplyVector(CameraVectorWS, GetPrimitiveData(Parameters).WorldToLocal);

Color = 0.0;

BlackHoleProperties BHP;

Mask = 1.0;

BHP.Mass = Mass;
BHP.EventHorizon = Mass*2.0;
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
BHP.ShadowColor = ShadowColor;
BHP.ShadowDensity = ShadowDensity;
BHP.ShadowStepSize = ShadowStepSize;
BHP.OrbitalBandSize = OrbitalBandSize;
BHP.AnimationScale = AnimationScale;
BHP.AnimExponent = AnimExponent;
BHP.ShadowSpread = ShadowSpread;
BHP.AtlasTexture = AtlasTexture;
BHP.AtlasTextureSampler = AtlasTextureSampler;
BHP.DopplerTexture = DopplerTexture;
BHP.DopplerTextureSampler = DopplerTextureSampler;
BHP.DopplerIntensity = DopplerIntensity;
BHP.BlackHolePos = BlackHolePos;
BHP.CameraPos = CameraPos;
BHP.DopplerExponent = DopplerExponent;
BHP.DopplerBias = DopplerBias;
BHP.CameraVector = CameraVector;
BHP.StepScale = StepScale;
BHP.VolumeStep = VolumeStep;
BHP.MaxSteps = MaxSteps;
BHP.Jitter = JitterAmount;

int3 RandPos = int3(Parameters.SvPosition.xy, View.StateFrameIndexMod8);
float Random = float(Rand3DPCG16(RandPos).x) / 0xffff;

float3 InitPos = CameraPositionLS;
float3 InitDir = normalize(CameraVectorLS);

Dir = InitDir;

Functions finalRender;
finalRender.BlackHole(Color, Mask, Dir, InitPos, Random, BHP);

return 1.0;