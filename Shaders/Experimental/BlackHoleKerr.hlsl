// Black Hole 2.0 · Kerr (spinning) black hole with a self-emitting accretion disk
// Custom node for M_BlackHole_Kerr · local space of the actor · spin axis = local +Z · disk in the local XY plane
// Disk Mapping: 0 = seamless turbulence repeated outward · 1 = one texture laid once from centre to edge (like 1.x)
// Outputs: Color (rgb = disk light, a = disk opacity) · Dir (local direction the ray leaves in) · Mask (1 = ray escaped)
// Units: lengths in local units (Mass sets the size) · G = c = 1

#define BH_PI 3.14159265

struct KerrBlackHole
{
    float M;
    float A;
    float RH;
    float RIn;
    float ROut;
    float Thickness;
    float FluxPeak;

    // ---------------- Kerr spacetime in Kerr-Schild coordinates ----------------

    float RadiusAt(float3 X)
    {
        float B = dot(X, X) - A * A;
        float R2 = 0.5 * B + sqrt(0.25 * B * B + A * A * X.z * X.z);
        return sqrt(max(R2, 1e-8));
    }

    void MetricAt(float3 X, out float R, out float F, out float3 L)
    {
        R = RadiusAt(X);
        float R2 = R * R;
        float Q = R2 * R2 + A * A * X.z * X.z;
        F = 2.0 * M * R2 * R / Q;
        float S = R2 + A * A;
        L = float3((R * X.x + A * X.y) / S, (R * X.y - A * X.x) / S, X.z / R);
    }

    void Derivatives(float3 X, float3 K, float Kt, out float3 DX, out float3 DK)
    {
        float R = RadiusAt(X);
        float R2 = R * R;
        float Q = R2 * R2 + A * A * X.z * X.z;
        float3 Rd = float3(R2 * R * X.x, R2 * R * X.y, R * X.z * (R2 + A * A)) / Q;

        float F = 2.0 * M * R2 * R / Q;
        float C1 = 2.0 * M / (Q * Q);
        float3 Fd = C1 * (3.0 * R2 * Rd * Q - R2 * R * (4.0 * R2 * R * Rd + float3(0.0, 0.0, 2.0 * A * A * X.z)));

        float S = R2 + A * A;
        float S2 = S * S;
        float3 L = float3((R * X.x + A * X.y) / S, (R * X.y - A * X.x) / S, X.z / R);

        float NX = R * X.x + A * X.y;
        float NY = R * X.y - A * X.x;
        float3 LXd = (float3(Rd.x * X.x + R, Rd.y * X.x + A, Rd.z * X.x) * S - NX * 2.0 * R * Rd) / S2;
        float3 LYd = (float3(Rd.x * X.y - A, Rd.y * X.y + R, Rd.z * X.y) * S - NY * 2.0 * R * Rd) / S2;
        float3 LZd = float3(0.0, 0.0, 1.0 / R) - X.z * Rd / R2;

        float LK = -Kt + dot(L, K);
        DX = K - F * LK * L;
        float3 DL = K.x * LXd + K.y * LYd + K.z * LZd;
        DK = 0.5 * LK * LK * Fd + F * LK * DL;
    }

    // ---------------- camera ----------------

    float MetricDot(float4 U, float4 V, float F, float4 LCov)
    {
        return -U.x * V.x + dot(U.yzw, V.yzw) + F * dot(LCov, U) * dot(LCov, V);
    }

    void CameraRay(float3 X, float3 D, out float3 K, out float Kt)
    {
        float R; float F; float3 L;
        MetricAt(X, R, F, L);
        float4 LCov = float4(1.0, L);

        float Alpha = rsqrt(1.0 + F);
        float4 U = Alpha * float4(1.0 + F, -F * L);

        float4 E[3];
        [unroll]
        for (int i = 0; i < 3; i++)
        {
            float4 V = float4(0.0, i == 0 ? 1.0 : 0.0, i == 1 ? 1.0 : 0.0, i == 2 ? 1.0 : 0.0);
            V += MetricDot(U, V, F, LCov) * U;
            [unroll]
            for (int j = 0; j < i; j++)
            {
                V -= MetricDot(E[j], V, F, LCov) * E[j];
            }
            E[i] = V * rsqrt(MetricDot(V, V, F, LCov));
        }

        float4 KUp = D.x * E[0] + D.y * E[1] + D.z * E[2] - U;
        float4 KCov = float4(-KUp.x, KUp.yzw) + F * dot(LCov, KUp) * LCov;
        K = KCov.yzw;
        Kt = KCov.x;
    }

    // ---------------- disk physics ----------------

    float Isco(float Chi)
    {
        float Z1 = 1.0 + pow(1.0 - Chi * Chi, 1.0 / 3.0) * (pow(1.0 + Chi, 1.0 / 3.0) + pow(1.0 - Chi, 1.0 / 3.0));
        float Z2 = sqrt(3.0 * Chi * Chi + Z1 * Z1);
        return M * (3.0 + Z2 - sqrt((3.0 - Z1) * (3.0 + Z1 + 2.0 * Z2)));
    }

    float PageThorne(float R)
    {
        float Chi = A / M;
        float X = sqrt(R / M);
        float X0 = sqrt(RIn / M);
        if (X <= X0)
        {
            return 0.0;
        }
        float Ac = acos(Chi);
        float X1 = 2.0 * cos((Ac - BH_PI) / 3.0);
        float X2 = 2.0 * cos((Ac + BH_PI) / 3.0);
        float X3 = -2.0 * cos(Ac / 3.0);
        X2 = abs(X2) < 1e-4 ? 1e-4 : X2;

        float T = X - X0 - 1.5 * Chi * log(X / X0);
        T -= 3.0 * (X1 - Chi) * (X1 - Chi) / (X1 * (X1 - X2) * (X1 - X3)) * log((X - X1) / (X0 - X1));
        T -= 3.0 * (X2 - Chi) * (X2 - Chi) / (X2 * (X2 - X1) * (X2 - X3)) * log((X - X2) / (X0 - X2));
        T -= 3.0 * (X3 - Chi) * (X3 - Chi) / (X3 * (X3 - X1) * (X3 - X2)) * log((X - X3) / (X0 - X3));
        return T / (X * X * X * X * (X * X * X - 3.0 * X + 2.0 * Chi)) / (M * M);
    }

    float FindFluxPeak()
    {
        float Lo = RIn;
        float Hi = RIn * 4.0;
        [loop]
        for (int i = 0; i < 14; i++)
        {
            float M1 = Hi - 0.6180339887 * (Hi - Lo);
            float M2 = Lo + 0.6180339887 * (Hi - Lo);
            if (PageThorne(M1) < PageThorne(M2))
            {
                Lo = M1;
            }
            else
            {
                Hi = M2;
            }
        }
        return PageThorne(0.5 * (Lo + Hi));
    }

    void Orbit(float R, out float Omega, out float Ut)
    {
        float SM = sqrt(M);
        float R15 = R * sqrt(R);
        Omega = SM / (R15 + A * SM);
        Ut = (R15 + A * SM) / (pow(R, 0.75) * sqrt(max(R15 - 3.0 * M * sqrt(R) + 2.0 * A * SM, 1e-6)));
    }

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
};

// ======================== main ========================

// Camera position and view direction in the actor's local space (transformed by engine nodes in the graph)
float3 CameraPositionLS = CameraPositionLocal;
float3 CameraVectorLS = -normalize(CameraVectorLocal);

int3 RandPos = int3(Parameters.SvPosition.xy, View.StateFrameIndexMod8);
float Random = float(Rand3DPCG16(RandPos).x) / 65535.0;
float BHTime = View.GameTime;

KerrBlackHole BH;
BH.M = max(Mass, 0.001);
BH.A = clamp(Spin, 0.0, 0.998) * BH.M;
BH.RH = BH.M + sqrt(max(BH.M * BH.M - BH.A * BH.A, 0.0));
BH.RIn = InnerRadius > 0.0 ? InnerRadius : BH.Isco(BH.A / BH.M);
BH.ROut = max(OuterRadius, BH.RIn * 1.5);
BH.Thickness = max(Thickness, 0.001);
BH.FluxPeak = BH.FindFluxPeak();

// Reverse Spin mirrors the scene, which flips the hole's spin and the disk's orbit together
float Mirror = ReverseSpin > 0.5 ? -1.0 : 1.0;
float3 X = CameraPositionLS * float3(1.0, Mirror, 1.0);
float3 D = CameraVectorLS * float3(1.0, Mirror, 1.0);

float EscapeRadius = max(20.0 * BH.ROut, 200.0 * BH.M);
Color = float4(0.0, 0.0, 0.0, 0.0);
Dir = CameraVectorLS;
Mask = 1.0;

// Far camera: travel in a straight line to the sphere where bending starts to matter
float R0 = length(X);
bool Skip = false;
if (R0 > EscapeRadius)
{
    float B = dot(X, D);
    float Disc = B * B - (R0 * R0 - EscapeRadius * EscapeRadius);
    if (Disc <= 0.0 || B > 0.0)
    {
        Skip = true;
    }
    else
    {
        X += D * (-B - sqrt(Disc));
    }
}

if (!Skip)
{
    float3 K; float Kt;
    BH.CameraRay(X, D, K, Kt);
    float KPhi = X.x * K.y - X.y * K.x;

    float Transmittance = 1.0;
    float3 Light = 0.0;
    bool Captured = true;
    float3 V = D;

    float GlowScale = Brightness * (1.0 + NormalizeBrightness * 0.52 * pow(max(6.0 * BH.M / BH.RIn - 1.0, 0.0), 1.78));
    float Phase1 = frac(BHTime / max(FlowPeriod, 0.01));
    float Phase2 = frac(Phase1 + 0.5);
    float Weight1 = 1.0 - abs(2.0 * Phase1 - 1.0);
    float TintLuma = max(dot(TintColor, float3(0.2126, 0.7152, 0.0722)), 1e-4);

    [loop]
    for (int i = 0; i < (int)MaxSteps; i++)
    {
        float R = BH.RadiusAt(X);
        if (R < BH.RH * 1.01)
        {
            break;
        }

        float3 DX1; float3 DK1;
        BH.Derivatives(X, K, Kt, DX1, DK1);
        V = DX1;
        float Speed = length(DX1);
        if (Speed > 1000.0)
        {
            break;
        }
        if (R > EscapeRadius && dot(X, DX1) > 0.0)
        {
            Captured = false;
            break;
        }

        // Step length in space: fixed inside the disk, growing with distance outside it
        float HZ = 3.0 * BH.Thickness * R;
        float StepLength;
        if (R > BH.RIn * 0.95 && R < BH.ROut && abs(X.z) < HZ)
        {
            StepLength = VolumeStep;
        }
        else
        {
            float DZ = (abs(X.z) - HZ) * rsqrt(1.0 + 9.0 * BH.Thickness * BH.Thickness);
            float DR = max(BH.RIn * 0.95 - R, R - BH.ROut);
            float DistToDisk = (DZ > 0.0 && DR > 0.0) ? length(float2(DZ, DR)) : max(DZ, DR);
            StepLength = min(StepScale * R, max(DistToDisk, 0.5 * VolumeStep));
        }

        // RK4 step along the light path
        float H = StepLength / Speed;
        float3 StepStart = X;
        float3 DX2; float3 DK2; float3 DX3; float3 DK3; float3 DX4; float3 DK4;
        BH.Derivatives(X + 0.5 * H * DX1, K + 0.5 * H * DK1, Kt, DX2, DK2);
        BH.Derivatives(X + 0.5 * H * DX2, K + 0.5 * H * DK2, Kt, DX3, DK3);
        BH.Derivatives(X + H * DX3, K + H * DK3, Kt, DX4, DK4);
        X += (H / 6.0) * (DX1 + 2.0 * DX2 + 2.0 * DX3 + DX4);
        K += (H / 6.0) * (DK1 + 2.0 * DK2 + 2.0 * DK3 + DK4);

        // Disk · sampled at a jittered point along this step, so the light path itself never changes between frames
        float3 S = lerp(StepStart, X, 1.0 - Jitter + Jitter * Random);
        R = BH.RadiusAt(S);
        float HH = BH.Thickness * R;
        if (R > BH.RIn * 0.95 && R < BH.ROut && abs(S.z) < 3.0 * HH)
        {
            float Vertical = exp(-0.5 * (S.z / HH) * (S.z / HH));
            float Fade = smoothstep(BH.RIn * 0.95, BH.RIn * 1.1, R) * (1.0 - smoothstep(BH.ROut * 0.75, BH.ROut, R));
            float Omega; float Ut;
            BH.Orbit(R, Omega, Ut);

            float U0 = atan2(S.y, S.x) / (2.0 * BH_PI) * TurbulenceRepeats;
            float V0 = lerp(log(R / BH.RIn) * TurbulenceRadialScale, R / BH.ROut, DiskMapping) + S.z / HH * (0.08 - 0.06 * DiskMapping);
            float Turn = Omega * OrbitSpeed * max(FlowPeriod, 0.01) / (2.0 * BH_PI) * TurbulenceRepeats;
            float2 N1 = TurbulenceTexture.SampleLevel(TurbulenceTextureSampler, float2(U0 - Turn * Phase1, V0), 0).rg;
            float2 N2 = TurbulenceTexture.SampleLevel(TurbulenceTextureSampler, float2(U0 - Turn * Phase2 + 0.37, V0 + 0.53), 0).rg;
            float2 N = N1 * Weight1 + N2 * (1.0 - Weight1);
            float Noise = N.x * 0.65 + N.y * 0.35;
            float Patches = max(1.0 + TurbulenceStrength * (smoothstep(0.3, 0.75, Noise) * 2.0 - 1.0), 0.0);
            float Density = Vertical * Fade * Patches;

            if (Density > 1e-4)
            {
                float Flux = BH.PageThorne(R) / BH.FluxPeak;
                float3 Glow = 0.0;
                if (Flux > 0.0)
                {
                    float G = 1.0 / (Ut * (Kt + Omega * KPhi));
                    G = 1.0 + DopplerStrength * (G - 1.0);
                    float3 Body = BH.Blackbody(PeakTemperature * pow(Flux, 0.25) * G);
                    float Luma = dot(Body, float3(0.2126, 0.7152, 0.0722));
                    Body = lerp(Body, Luma * TintColor / TintLuma, TintAmount);
                    Glow = Body * GlowScale * pow(Flux, RadialFalloff) * pow(G, 4.0) * Patches;
                }
                float Absorbed = 1.0 - exp(-Opacity * Density * StepLength);
                Light += Transmittance * Glow * Absorbed;
                Transmittance *= 1.0 - Absorbed;
                if (Transmittance < 0.01)
                {
                    break;
                }
            }
        }
    }

    Color = float4(Light, 1.0 - Transmittance);
    Mask = Captured ? 0.0 : 1.0;
    Dir = normalize(V) * float3(1.0, Mirror, 1.0);
}

return 1.0;
