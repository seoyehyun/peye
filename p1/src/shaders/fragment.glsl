#define PI 3.141592

uniform float time;
uniform float uAudioLevel;
uniform float uStripeDensity;
uniform float uNormalIntensity;
uniform float uMaterialMode;

varying vec2 vUv;
varying vec3 vPosition;
varying vec3 vNormal;
varying float vHeight;
varying vec3 vSphereDir;

#define SPIRAL_SPEED 0.7

vec3 pal(in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d) {
  return a + b * cos(6.28318 * (c * t + d));
}

vec3 spectrum(float t) {
  return pal(
    t,
    vec3(0.5, 0.5, 0.5),
    vec3(0.5, 0.0, 0.5),
    vec3(1.0, 1.0, 1.0),
    vec3(0.2, 0.33, 0.67)
  );
}

vec3 cartesianToPolar(vec3 p) {
  float r = length(p);
  float theta = acos(clamp(p.z / max(r, 0.0001), -1.0, 1.0));
  float phi = atan(p.y, p.x);
  return vec3(r, theta, phi);
}

float spiralHeight(vec3 dir) {
  dir = normalize(dir);
  float angle = atan(dir.z, dir.x);
  float latitude = dir.y;
  float radialMask = pow(max(1.0 - abs(latitude), 0.0), 0.55);
  float spacing = clamp(uStripeDensity, 0.0, 1.0);
  float turns = max(1.0, floor(mix(2.0, 18.0, spacing) + 0.5));
  float pitch = mix(3.0, 22.0, spacing) * mix(0.95, 1.25, uAudioLevel);
  float t = time * SPIRAL_SPEED;

  float spiralA = sin(angle * turns + latitude * pitch - t);
  float spiralB = sin(angle * (turns + 2.0) - latitude * (pitch * 0.55) - t * 0.72);
  float spiralC = sin(angle * max(1.0, turns - 1.0) + latitude * (pitch * 1.35) + t * 0.48);
  float wave = spiralA * 0.62 + spiralB * 0.24 + spiralC * 0.14;
  return wave * radialMask;
}

vec3 calculateSpiralNormal(vec3 sphereDir, vec3 baseNormal, float eps) {
  vec3 tangent = normalize(cross(vec3(0.0, 1.0, 0.0), baseNormal));
  if (length(tangent) < 0.001) {
    tangent = normalize(cross(vec3(1.0, 0.0, 0.0), baseNormal));
  }

  vec3 bitangent = normalize(cross(baseNormal, tangent));

  float h = spiralHeight(sphereDir);
  float ht = spiralHeight(normalize(sphereDir + tangent * eps));
  float hb = spiralHeight(normalize(sphereDir + bitangent * eps));

  vec3 displacedTangent = tangent + baseNormal * (ht - h);
  vec3 displacedBitangent = bitangent + baseNormal * (hb - h);
  return normalize(cross(displacedBitangent, displacedTangent));
}

void main() {
  float eps = 0.035;
  vec3 sphereDir = normalize(vSphereDir);
  vec3 baseNormal = normalize(vNormal);
  vec3 waveNormal = calculateSpiralNormal(sphereDir, baseNormal, eps);
  float normalMix = clamp(uAudioLevel * uNormalIntensity, 0.0, 1.0);
  vec3 n = normalize(mix(baseNormal, waveNormal, normalMix));
  int materialMode = int(uMaterialMode + 0.5);

  if (materialMode == 0) {
    vec3 normalViz = (n + 1.0) * 0.5;
    gl_FragColor = vec4(normalViz, 1.0);
    return;
  }

  vec3 viewDir = normalize(cameraPosition - vPosition);
  vec3 polar = cartesianToPolar(sphereDir);
  vec3 reflectDir = reflect(-viewDir, n);
  float latBand = sin(polar.y * 20.0 - time * 1.25);
  float swirlBand = sin(polar.z * 6.0 + polar.y * 5.5 + time * 0.75);
  float ribbon = 0.5 + 0.5 * (latBand * 0.7 + swirlBand * 0.3);
  float spectralT = fract(polar.z / (2.0 * PI) + polar.y / PI * 0.45 + ribbon * 0.08);

  vec3 spectral = spectrum(spectralT);
  vec3 glassTint = mix(vec3(0.08, 0.12, 0.18), spectral, 0.65);
  vec3 innerTint = mix(vec3(0.02, 0.03, 0.05), glassTint, 0.55);
  float fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.8);
  float env = reflectDir.y * 0.5 + 0.5;
  float rim = pow(1.0 - max(dot(n, viewDir), 0.0), 2.6);
  float causticBand = pow(ribbon, 2.4);

  vec3 envColor = mix(vec3(0.01, 0.015, 0.03), vec3(0.82, 0.9, 1.0), smoothstep(0.0, 1.0, env));
  envColor += vec3(0.25, 0.35, 0.55) * causticBand * 0.25;
  vec3 lightDir = normalize(vec3(-0.4, 0.5, 1.0));
  vec3 halfDir = normalize(lightDir + viewDir);
  float ndl = max(dot(n, lightDir), 0.0);
  float spec = pow(max(dot(n, halfDir), 0.0), 90.0);
  float sharpSpec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 180.0);

  vec3 glass = innerTint * 0.4;
  glass += spectral * ribbon * 0.28;
  glass += envColor * 0.5;
  glass += ndl * vec3(0.05, 0.07, 0.11);
  glass += rim * mix(vec3(0.35, 0.45, 0.6), spectral, 0.45);
  glass += fresnel * mix(vec3(0.55, 0.7, 0.9), spectral, 0.35);
  glass += spec * vec3(0.95, 0.98, 1.0);
  glass += sharpSpec * vec3(1.0);

  gl_FragColor = vec4(clamp(glass, 0.0, 1.0), 1.0);
}
