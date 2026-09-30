// Post-FX for the whole screen. All effects live in this one shader and the
// `effect` uniform picks one, because switching between shaders (or turning a
// shader off) at runtime is unreliable in DragonRuby 7.21 and can crash it.
//   0 off, 1 glow + grade, 2 CRT, 3 retro dither, 4 haze
Texture2D tex_scene : register(t0, space2);
SamplerState sam_scene : register(s0, space2);

cbuffer Uniforms : register(b0, space3) {
  float time;
  float width;
  float height;
  float strength;
  float effect;
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

float4 scene(float2 uv) {
  return tex_scene.Sample(sam_scene, uv);
}

// Cheap single-pass bloom (bright taps on two rings), warm/cool split tone
// and vignette.
float3 bright(float2 uv) {
  float3 c = scene(uv).rgb;
  float l = dot(c, float3(0.2126, 0.7152, 0.0722));
  return c * saturate((l - 0.45) * 2.5);
}

float4 glow(float2 uv) {
  float4 base = scene(uv);
  float2 px = float2(1.0 / width, 1.0 / height);
  float3 bloom = float3(0.0, 0.0, 0.0);
  for (int i = 0; i < 12; i++) {
    float a = i * 0.5236;
    float2 dir = float2(cos(a), sin(a)) * px;
    bloom += bright(uv + dir * 5.0) * 0.6;
    bloom += bright(uv + dir * 13.0) * 0.4;
  }
  float3 c = base.rgb + bloom / 12.0 * 1.6 * strength;
  float l = dot(c, float3(0.2126, 0.7152, 0.0722));
  c = lerp(c * float3(0.9, 0.97, 1.12), c * float3(1.08, 1.0, 0.9), saturate(l * 1.5));
  float2 d = uv - 0.5;
  c *= 1.0 - dot(d, d) * 1.1 * strength;
  return float4(c, base.a);
}

// CRT monitor: barrel distortion, RGB split, scanlines, vignette.
float4 crt(float2 tex_uv) {
  float2 d = tex_uv - 0.5;
  float2 uv = 0.5 + d * (1.0 + dot(d, d) * 0.22 * strength);
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return float4(0.0, 0.0, 0.0, 1.0);
  }
  float split = 1.6 * strength / width;
  float3 c;
  c.r = scene(uv + float2(split, 0.0)).r;
  c.g = scene(uv).g;
  c.b = scene(uv - float2(split, 0.0)).b;
  float scan = 0.5 + 0.5 * sin(uv.y * height * 3.14159);
  c *= lerp(1.0, 0.72 + 0.28 * scan, strength);
  c *= 1.0 + 0.015 * sin(time * 50.0) * strength;
  float2 e = uv - 0.5;
  c *= 1.0 - dot(e, e) * 1.4 * strength;
  return float4(c * 1.12, 1.0);
}

// Low resolution (320x180 blocks) with 4x4 Bayer ordered dithering down to a
// few colour levels per channel.
static const float BAYER[16] = {
   0.0,  8.0,  2.0, 10.0,
  12.0,  4.0, 14.0,  6.0,
   3.0, 11.0,  1.0,  9.0,
  15.0,  7.0, 13.0,  5.0
};

float4 retro(float2 tex_uv) {
  float2 res = float2(320.0, 180.0);
  float2 cell = floor(tex_uv * res);
  float4 c = scene((cell + 0.5) / res);
  int2 p = int2(fmod(cell, 4.0));
  float threshold = BAYER[p.y * 4 + p.x] / 16.0 - 0.5;
  float levels = lerp(12.0, 4.0, strength);
  float3 q = floor(c.rgb * (levels - 1.0) + 0.5 + threshold) / (levels - 1.0);
  return float4(saturate(q), c.a);
}

// Underwater / heat haze: animated sine UV warp, tint, moving caustics.
float4 haze(float2 tex_uv) {
  float2 warp = float2(sin(tex_uv.y * 23.0 + time * 1.7) + sin(tex_uv.y * 41.0 - time * 2.3) * 0.5,
                       cos(tex_uv.x * 19.0 + time * 1.3) + cos(tex_uv.x * 37.0 + time * 2.9) * 0.5);
  float2 uv = saturate(tex_uv + warp * 0.0035 * strength);
  float4 c = scene(uv);
  float caustic = sin(uv.x * 40.0 + time * 1.1) * sin(uv.y * 30.0 - time * 1.4);
  caustic = pow(saturate(caustic), 6.0) * 0.25;
  float3 tinted = c.rgb * float3(0.65, 0.95, 1.1) + float3(0.0, 0.03, 0.06) + caustic;
  return float4(lerp(c.rgb, tinted, strength), c.a);
}

Output main(Input input) {
  Output output;
  float2 uv = input.tex_coord;
  int fx = (int)(effect + 0.5);
  float4 c;
  if (fx == 1) {
    c = glow(uv);
  } else if (fx == 2) {
    c = crt(uv);
  } else if (fx == 3) {
    c = retro(uv);
  } else if (fx == 4) {
    c = haze(uv);
  } else {
    c = scene(uv);
  }
  output.frag_color = c * input.tex_color;
  return output;
}
