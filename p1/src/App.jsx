import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import "./App.css";
import vertexShaderSource from "./shaders/vertex.glsl?raw";
import fragmentShaderSource from "./shaders/fragment.glsl?raw";

const soundModules = import.meta.glob("./sounds/*.mp3", {
  eager: true,
  import: "default",
});

const soundOptions = Object.entries(soundModules)
  .map(([path, src]) => ({
    label: path.split("/").pop()?.replace(/\.mp3$/i, "") ?? path,
    src,
  }))
  .sort((a, b) => a.label.localeCompare(b.label));

export default function App() {
  const [stripeSpacing, setStripeSpacing] = useState(0.5);
  const [volume, setVolume] = useState(0.5);
  const [intensity, setIntensity] = useState(0.7);
  const [materialMode, setMaterialMode] = useState(0);
  const [selectedSound, setSelectedSound] = useState(soundOptions[0]?.src ?? "");
  const [isPlaying, setIsPlaying] = useState(false);
  const containerRef = useRef(null);
  const rendererRef = useRef(null);
  const startTimeRef = useRef(Date.now());
  const sphereRef = useRef(null);
  const materialRef = useRef(null);
  const cameraRef = useRef(null);
  const audioElementRef = useRef(null);
  const audioContextRef = useRef(null);
  const analyserRef = useRef(null);
  const frequencyDataRef = useRef(null);
  const audioLevelRef = useRef(0);
  const audioTargetRef = useRef(0);
  const mediaSourceRef = useRef(null);
  const stripeSpacingRef = useRef(0.5);
  const volumeRef = useRef(0.25);
  const intensityRef = useRef(1);
  const cameraDistanceRef = useRef(3);

  // Arcball state
  const mouseRef = useRef({ x: 0, y: 0 });
  const prevMouseRef = useRef({ x: 0, y: 0 });
  const isMouseDownRef = useRef(false);

  useEffect(() => {
    if (!containerRef.current) return;

    const width = containerRef.current.clientWidth;
    const height = containerRef.current.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });

    renderer.setSize(width, height);
    renderer.setClearColor(0x000000);
    containerRef.current.appendChild(renderer.domElement);

    camera.position.z = 3;
    cameraRef.current = camera;

    const geometry = new THREE.SphereGeometry(1, 256, 256);
    const material = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        uAudioLevel: { value: 0 },
        uStripeDensity: { value: stripeSpacing },
        uNormalIntensity: { value: volume * intensity },
        uMaterialMode: { value: materialMode },
      },
      vertexShader: vertexShaderSource,
      fragmentShader: fragmentShaderSource,
    });

    const sphere = new THREE.Mesh(geometry, material);
    scene.add(sphere);
    sphereRef.current = sphere;

    rendererRef.current = renderer;
    materialRef.current = material;

    const handleMouseDown = (e) => {
      if (e.button !== 2) return;
      e.preventDefault();
      isMouseDownRef.current = true;
      prevMouseRef.current = { x: e.clientX, y: e.clientY };
    };

    const handleMouseMove = (e) => {
      mouseRef.current = { x: e.clientX, y: e.clientY };

      if (isMouseDownRef.current) {
        const deltaX = e.clientX - prevMouseRef.current.x;
        const deltaY = e.clientY - prevMouseRef.current.y;

        sphere.rotation.y += deltaX * 0.005;
        sphere.rotation.x += deltaY * 0.005;

        prevMouseRef.current = { x: e.clientX, y: e.clientY };
      }
    };

    const handleMouseUp = () => {
      isMouseDownRef.current = false;
    };

    const handleContextMenu = (e) => {
      e.preventDefault();
    };

    const handleWheel = (e) => {
      e.preventDefault();
      cameraDistanceRef.current = THREE.MathUtils.clamp(
        cameraDistanceRef.current + e.deltaY * 0.0005,
        1.4,
        6
      );
      camera.position.z = cameraDistanceRef.current;
    };

    containerRef.current.addEventListener("mousedown", handleMouseDown);
    containerRef.current.addEventListener("mousemove", handleMouseMove);
    containerRef.current.addEventListener("mouseup", handleMouseUp);
    containerRef.current.addEventListener("mouseleave", handleMouseUp);
    containerRef.current.addEventListener("contextmenu", handleContextMenu);
    containerRef.current.addEventListener("wheel", handleWheel, { passive: false });

    const handleResize = () => {
      if (!containerRef.current) return;
      const newWidth = containerRef.current.clientWidth;
      const newHeight = containerRef.current.clientHeight;
      camera.aspect = newWidth / newHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(newWidth, newHeight);
    };

    window.addEventListener("resize", handleResize);

    const animate = () => {
      requestAnimationFrame(animate);

      const elapsed = (Date.now() - startTimeRef.current) * 0.001;
      material.uniforms.time.value = elapsed;

      if (analyserRef.current && frequencyDataRef.current) {
        analyserRef.current.getByteFrequencyData(frequencyDataRef.current);

        let weightedTotal = 0;
        let weightSum = 0;
        for (let i = 0; i < frequencyDataRef.current.length; i += 1) {
          const normalizedIndex = i / frequencyDataRef.current.length;
          const sample = frequencyDataRef.current[i];
          const weight = 1.4 - normalizedIndex * 0.75;

          weightedTotal += sample * weight;
          weightSum += weight;
        }

        const average = weightedTotal / Math.max(weightSum * 255, 0.0001);
        audioTargetRef.current = Math.min(Math.pow(average * 2.0, 1.08), 1);
      } else {
        audioTargetRef.current = 0;
      }

      const smoothing = audioTargetRef.current > audioLevelRef.current ? 0.08 : 0.045;
      audioLevelRef.current = THREE.MathUtils.lerp(
        audioLevelRef.current,
        audioTargetRef.current,
        smoothing
      );

      material.uniforms.uAudioLevel.value = audioLevelRef.current;
      material.uniforms.uStripeDensity.value = stripeSpacingRef.current;
      const normalIntensityValue = volumeRef.current * intensityRef.current;
      material.uniforms.uNormalIntensity.value = normalIntensityValue;
      const sphereScale = 1.0 + normalIntensityValue * 0.5;
      sphere.scale.setScalar(sphereScale);

      renderer.render(scene, camera);
    };

    animate();

    return () => {
      window.removeEventListener("resize", handleResize);
      if (containerRef.current) {
        containerRef.current.removeEventListener("mousedown", handleMouseDown);
        containerRef.current.removeEventListener("mousemove", handleMouseMove);
        containerRef.current.removeEventListener("mouseup", handleMouseUp);
        containerRef.current.removeEventListener("mouseleave", handleMouseUp);
        containerRef.current.removeEventListener("contextmenu", handleContextMenu);
        containerRef.current.removeEventListener("wheel", handleWheel);
      }
      renderer.dispose();
      geometry.dispose();
      material.dispose();
      materialRef.current = null;
      if (audioElementRef.current) {
        audioElementRef.current.pause();
        audioElementRef.current.src = "";
      }
      if (audioContextRef.current) {
        audioContextRef.current.close();
      }
      if (
        containerRef.current &&
        renderer.domElement.parentNode === containerRef.current
      ) {
        containerRef.current.removeChild(renderer.domElement);
      }
      cameraRef.current = null;
    };
  }, []);

  useEffect(() => {
    stripeSpacingRef.current = stripeSpacing;
    if (!materialRef.current) return;
    materialRef.current.uniforms.uStripeDensity.value = stripeSpacing;
  }, [stripeSpacing]);

  useEffect(() => {
    volumeRef.current = volume;
    if (!materialRef.current) return;
    materialRef.current.uniforms.uNormalIntensity.value =
      volume * intensityRef.current;
    if (audioElementRef.current) {
      audioElementRef.current.volume = Math.min(volume * 2, 1);
    }
  }, [volume]);

  useEffect(() => {
    intensityRef.current = intensity;
    if (!materialRef.current) return;
    materialRef.current.uniforms.uNormalIntensity.value =
      volumeRef.current * intensity;
  }, [intensity]);

  useEffect(() => {
    if (!materialRef.current) return;
    materialRef.current.uniforms.uMaterialMode.value = materialMode;
  }, [materialMode]);

  useEffect(() => {
    if (!audioElementRef.current) {
      audioElementRef.current = new Audio();
      audioElementRef.current.crossOrigin = "anonymous";
      audioElementRef.current.loop = true;
    }

    const audio = audioElementRef.current;
    audio.src = selectedSound;
    audio.load();
    audio.volume = Math.min(volumeRef.current * 2, 1);

    if (isPlaying) {
      void audio.play().catch(() => {
        setIsPlaying(false);
      });
    }
  }, [selectedSound, isPlaying]);

  const ensureAudioGraph = async () => {
    if (!audioElementRef.current) {
      audioElementRef.current = new Audio();
      audioElementRef.current.crossOrigin = "anonymous";
      audioElementRef.current.loop = true;
    }

    if (!audioContextRef.current) {
      const audioContext = new window.AudioContext();
      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 256;
      analyser.smoothingTimeConstant = 0.85;

      const mediaSource = audioContext.createMediaElementSource(audioElementRef.current);
      mediaSource.connect(analyser);
      analyser.connect(audioContext.destination);

      audioContextRef.current = audioContext;
      analyserRef.current = analyser;
      frequencyDataRef.current = new Uint8Array(analyser.frequencyBinCount);
      mediaSourceRef.current = mediaSource;
    }

    if (audioContextRef.current.state === "suspended") {
      await audioContextRef.current.resume();
    }
  };

  const handleToggleAudio = async () => {
    if (!selectedSound) return;

    if (!isPlaying) {
      await ensureAudioGraph();
      try {
        await audioElementRef.current.play();
        setIsPlaying(true);
      } catch {
        setIsPlaying(false);
      }
      return;
    }

    audioElementRef.current.pause();
    setIsPlaying(false);
  };

  const handleSoundChange = (event) => {
    setSelectedSound(event.target.value);
    audioLevelRef.current = 0;
    audioTargetRef.current = 0;
  };

  const handleCycleMaterial = () => {
    setMaterialMode((prev) => {
      const next = (prev + 1) % 2;
      if (materialRef.current) {
        materialRef.current.uniforms.uMaterialMode.value = next;
      }
      return next;
    });
  };

  return (
    <div ref={containerRef} className="app-container">
      <div className="control-panel">
        <label className="control-group">
          <span>Sound</span>
          <select value={selectedSound} onChange={handleSoundChange}>
            {soundOptions.map((sound) => (
              <option key={sound.src} value={sound.src}>
                {sound.label}
              </option>
            ))}
          </select>
        </label>

        <button type="button" className="audio-button" onClick={handleToggleAudio}>
          {isPlaying ? "Pause Audio" : "Play Audio"}
        </button>

        <button type="button" className="audio-button" onClick={handleCycleMaterial}>
          {materialMode === 0 ? "Normal" : "Glass"}
        </button>

        <label className="control-group">
          <span>Stripe Spacing</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={stripeSpacing}
            onChange={(e) => setStripeSpacing(Number(e.target.value))}
          />
          <strong>{stripeSpacing.toFixed(2)}</strong>
        </label>

        <label className="control-group">
          <span>Volume</span>
          <input
            type="range"
            min="0"
            max="0.5"
            step="0.01"
            value={volume}
            onChange={(e) => setVolume(Number(e.target.value))}
          />
          <strong>{(volume * 2).toFixed(2)}</strong>
        </label>

        <label className="control-group">
          <span>Intensity</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={intensity}
            onChange={(e) => setIntensity(Number(e.target.value))}
          />
          <strong>{intensity.toFixed(2)}</strong>
        </label>
      </div>
    </div>
  );
}
