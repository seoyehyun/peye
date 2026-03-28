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

float sampleSurfaceRadius(vec3 dir) {
  float displacementAmount = clamp(uAudioLevel * uNormalIntensity * 1.43, 0.0, 1.0);
  return 1.0 + spiralHeight(normalize(dir)) * displacementAmount;
}

float fakeSelfShadow(vec3 sphereDir, vec3 lightDir) {
  float shadow = 1.0;
  float baseRadius = sampleSurfaceRadius(sphereDir);

  for (int i = 1; i <= 6; i++) {
    float stepSize = 0.038 * float(i);
    vec3 probeDir = normalize(sphereDir + lightDir * stepSize);
    float probeRadius = sampleSurfaceRadius(probeDir);
    float expectedRadius = baseRadius - stepSize * 0.22;
    float occlusion = smoothstep(expectedRadius + 0.008, expectedRadius + 0.075, probeRadius);
    shadow *= mix(1.0, 0.8, occlusion);
  }

  return clamp(shadow, 0.45, 1.0);
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
  if (materialMode == 1) {
    // vHeight is negative in recessed regions and positive on protrusions.
    float t = clamp(vHeight * 0.35 + 0.5, 0.0, 1.0);
    vec3 color = vec3(1.0);
    color = mix(color, vec3(1.0, 0.9, 0.18), smoothstep(0.2, 0.35, t));
    color = mix(color, vec3(1.0, 0.42, 0.04), smoothstep(0.35, 0.38, t));
    color = mix(color, vec3(0.85, 0.25, 0.06), smoothstep(0.38, 0.40, t));
    color = mix(color, vec3(0.78, 0.06, 0.08), smoothstep(0.4, 0.41, t));
    color = mix(color, vec3(0.22, 0.02, 0.32), smoothstep(0.41, 0.6, t));
    color = mix(color, vec3(0.0), smoothstep(0.6, 1.0, t));

    float facing = clamp(dot(n, viewDir), 0.0, 1.0);
    float rimGlow = pow(1.0 - facing, 2.2);
    float coreGlow = pow(1.0 - t, 1.6);
    float pulse = 0.82 + 0.18 * sin(time * 1.2 + t * 4.0);
    vec3 glowColor = mix(vec3(1.0, 0.45, 0.08), vec3(1.0, 0.9, 0.18), 1.0 - t);

    color += glowColor * coreGlow * 0.35 * pulse;
    color += glowColor * rimGlow * 0.28;
    color += vec3(1.0, 0.55, 0.12) * pow(max(0.0, 1.0 - abs(t - 0.32) * 3.5), 2.0) * 0.12;

    gl_FragColor = vec4(color, 1.0);
    return;
  }

  if (materialMode == 3) {
    bool isFrontFace = gl_FrontFacing;
    float facing = clamp(dot(n, viewDir), 0.0, 1.0);
    float rim = pow(1.0 - facing, 2.0);
    float innerGlow = pow(facing, 1.2);
    float outerGlow = pow(1.0 - facing, 1.35);
    float thickness = pow(1.0 - facing, 0.65);
    vec3 refractedDir = refract(-viewDir, n, 0.78);
    float distortion = refractedDir.x * 0.5 + refractedDir.y * 0.35 + refractedDir.z * 0.15;
    float jellyBand = 0.5 + 0.5 * sin(vHeight * 12.0 + time * 1.6 + distortion * 10.0);
    float innerSwirl = 0.5 + 0.5 * sin(
      refractedDir.y * 9.0 +
      refractedDir.x * 7.0 +
      vHeight * 10.0 -
      time * 1.1
    );
    vec3 deepJelly = vec3(0.05, 0.38, 0.16);
    vec3 midJelly = vec3(0.15, 0.72, 0.28);
    vec3 brightJelly = vec3(0.62, 1.0, 0.72);
    vec3 jelly = mix(deepJelly, midJelly, facing);
    jelly = mix(jelly, brightJelly, rim * 0.45 + jellyBand * 0.18);
    jelly = mix(jelly, vec3(0.1, 0.52, 0.2), innerSwirl * thickness * 0.22);

    vec3 lightPos = vec3(2.6, 1.9, 3.4);
    vec3 lightDir = normalize(lightPos - vPosition);
    vec3 halfDir = normalize(lightDir + viewDir);
    float ndl = max(dot(n, lightDir), 0.0);
    float spec = pow(max(dot(n, halfDir), 0.0), 70.0);
    float transmission = pow(max(dot(-lightDir, refractedDir), 0.0), 2.2);
    jelly += vec3(0.22, 0.5, 0.2) * ndl * 0.22;
    jelly += vec3(0.85, 1.0, 0.86) * spec * 0.55;
    jelly += vec3(0.35, 0.95, 0.42) * innerGlow * 0.32;
    jelly += vec3(0.55, 1.0, 0.62) * rim * 0.34;
    jelly += vec3(0.42, 1.0, 0.5) * outerGlow * 0.22;
    jelly += vec3(0.28, 0.9, 0.36) * jellyBand * 0.1;
    jelly += vec3(0.4, 1.0, 0.48) * transmission * thickness * 0.35;
    jelly += vec3(0.12, 0.4, 0.18) * thickness * 0.28;
    jelly += vec3(0.28, 0.95, 0.34) * (0.82 + 0.18 * sin(time * 1.8)) * innerGlow * 0.16;

    float alpha = mix(0.3, 0.95, pow(facing, 1.7));
    if (!isFrontFace) {
      jelly *= vec3(0.34, 0.5, 0.38);
      alpha *= 0.22;
    }
    gl_FragColor = vec4(clamp(jelly, 0.0, 1.0), alpha);
    return;
  }

  vec3 lightPos = vec3(2.6, 1.9, 3.4);
  vec3 lightDir = normalize(lightPos - vPosition);
  vec3 halfDir = normalize(lightDir + viewDir);
  vec3 reflectDir = reflect(-viewDir, n);
  float ndl = max(dot(n, lightDir), 0.0);
  float ndv = max(dot(n, viewDir), 0.0);
  float selfShadow = fakeSelfShadow(sphereDir, lightDir);
  float fresnel = pow(1.0 - ndv, 5.0);
  float specular = pow(max(dot(n, halfDir), 0.0), 110.0);
  float sharpSpecular = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 180.0);
  float env = reflectDir.y * 0.5 + 0.5;
  float horizon = pow(1.0 - abs(reflectDir.y), 4.5);
  float shadowMask = pow(1.0 - ndl, 1.35);
  float edgeShadow = pow(1.0 - ndv, 1.7);
  float skyBounce = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
  float facingLight = pow(ndl, 1.05);
  float facingView = pow(ndv, 0.9);

  vec3 darkMetal = vec3(0.012, 0.014, 0.018);
  vec3 midMetal = vec3(0.32, 0.34, 0.38);
  vec3 brightMetal = vec3(0.96, 0.97, 0.99);
  vec3 envColor = mix(darkMetal, brightMetal, smoothstep(0.1, 1.0, env));
  envColor = mix(envColor, midMetal, 0.22);
  envColor += vec3(0.86, 0.9, 0.96) * horizon * 0.45;
  envColor += vec3(0.18, 0.2, 0.24) * skyBounce * 0.18;

  vec3 metal = envColor * 0.68;
  metal -= vec3(0.22, 0.23, 0.26) * shadowMask;
  metal -= vec3(0.1, 0.11, 0.13) * edgeShadow * (1.0 - fresnel);
  metal *= selfShadow;
  metal += facingLight * vec3(0.07, 0.075, 0.085) * selfShadow;
  metal += specular * vec3(1.45) * selfShadow;
  metal += sharpSpecular * vec3(1.25, 1.28, 1.32);
  metal += fresnel * vec3(0.62, 0.66, 0.74);
  metal += envColor * fresnel * 0.18;
  metal += vec3(0.08, 0.085, 0.095) * facingView * 0.08;

  gl_FragColor = vec4(clamp(metal, 0.0, 1.0), 1.0);
}
