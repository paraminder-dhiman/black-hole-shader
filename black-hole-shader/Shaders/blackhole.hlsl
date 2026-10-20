#define STEPS 5000
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
        
    float Cross2(float3 A, float3 B)
    {
        return pow((A.y*B.z) - (B.y*A.z), 2.0) + pow((A.z*B.x) - (A.x*B.z), 2.0) + pow((A.x*B.y) - (A.y*B.x), 2.0);
    }

    float3 GravityForce(float3 RayPos, float3 RayDir, BlackHoleProperties BHP)
    {
        RayDir = normalize(RayDir);
        float DistToSingularity = length(RayPos);
        float SquaredDistance = DistToSingularity * DistToSingularity;
        float3 SingularityToPos = normalize(RayPos);

        return (-3.0 * BHP.Mass) / SquaredDistance * Cross2(SingularityToPos, RayDir) * SingularityToPos;
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

    void StepRay(inout float3 RayPos, inout float3 RayDir, out float3 PrevPos, BlackHoleProperties BHP)
    {
        //Store Previous Position
        PrevPos = RayPos;

        //Calculates new Position and Direction of the Ray
        RayPos += RayDir + GravityForce(RayPos, RayDir, BHP);
        RayDir = normalize(RayPos - PrevPos);
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
        Density *= (1.0/ (1.0 - Attenuation));

        Density *= BHP.DiskDensity * DiskMask(RayPosition, BHP);

        return float4(DiskColor.xyz, Density);
    }

    void BlackHole(inout float4 Color, inout float Mask, inout float3 Dir, float3 CameraPosition, BlackHoleProperties BHP)
    {
        float3 RayPos = CameraPosition;
        float3 RayDir = Dir;
        float3 PrevPos;

        float Transmittance = 1.0;

        float3 LightDir = 0.0;

        float3 RayColor = 0.0;
        

        //Begin Raymarch
        
        for(int i = 0; i < STEPS; i++)
        {
            if(CrossedEventHorizon(RayPos, BHP))
            {
                Mask = 0;
                break;
            }
            
            StepRay(RayPos, RayDir, PrevPos, BHP);
            //float DopplerColor = mainDoppler(RayPos, BHP);

            float DensitySample = 0;

            if(InFogVolume(RayPos, BHP))
            {
                float FogSample = SampleFogDensity(RayPos, BHP); //Sample Fog
                float4 FogDiskSample = SampleDisk(RayPos, 6, BHP);

                //Light Energy Calculation
                float3 LightEnergy = CalculateLighting(RayPos, BHP) * BHP.LightColor * BHP.LightIntensity;

                float3 FogEnergy = LightEnergy * FogDiskSample.xyz;

                //Sample Disk Density
                float4 DiskSample = SampleDisk(RayPos, 0, BHP);  
                float3 DiskEnergy = LightEnergy * DiskSample.xyz;


                //Lighting
                //Initialize Lighting Variables
                float3 LightingPos = RayPos;
                LightDir = normalize(-LightingPos);
                float ShadowAccumulation = 0;

                if(DiskSample.w + FogSample > 0.0001)
                {
                    //Shadow Loop
                    for(int j = 0; j < SHADOWSTEPS; j++)
                    {
                        //Is Lighting Position inside volume?
                        if(InFogVolume(LightingPos, BHP))
                        {
                            //Sample Density at Lighting Position, Accumulate that value and then step position forward along the ray
                            float LightSampleFog = SampleFogDensity(RayPos, BHP);
                            float LightSampleDisk = SampleDisk(LightingPos, j*(BHP.ShadowSpread), BHP).w; //LightSample += SampleDisk(LightingPos, 0, BHP);

                            ShadowAccumulation += LightSampleFog + LightSampleDisk;
                            LightingPos += LightDir * BHP.ShadowStepSize;
                        }
                    }
                }
                
                DensitySample = FogSample + DiskSample.w;

                float3 Absorption = exp(-ShadowAccumulation * BHP.ShadowDensity * BHP.ShadowColor) * DensitySample;

                RayColor += FogEnergy * Transmittance * DensitySample * Absorption;
                RayColor += DiskEnergy * Transmittance * DensitySample * Absorption;
                Transmittance *= saturate(1.0 - DensitySample);
                if(Transmittance < 0.00001) break;
            }
        
        }

        Color = float4(RayColor, 1.0 - Transmittance);
        Dir = RayDir;
    }

};

float3 CameraPositionWS = LWCToFloat(ResolvedView.WorldCameraOrigin);
float3 CameraVectorWS = -Parameters.CameraVector;

//World to Local Transform
FDFInverseMatrix WorldToLocal = DFFromTileOffset(GetWorldToInstance(Parameters));
float3 Scale = DFMultiplyVector(float3(1.0, 0, 0), DFFromTileOffset(GetInstanceToWorld(Parameters)));
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

int3 RandPos = int3(Parameters.SvPosition.xy, View.StateFrameIndexMod8);
float Random = float(Rand3DPCG16(RandPos).x) / 0xffff;

float3 InitPos = CameraPositionLS;
float3 InitDir = CameraVectorLS;

Dir = InitDir;
InitPos += InitDir * Random * JitterAmount * Scale.x;


Functions finalRender;
finalRender.BlackHole(Color, Mask, Dir, InitPos, BHP);

return 1.0;