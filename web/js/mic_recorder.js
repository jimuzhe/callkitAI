(function () {
  const TARGET_SAMPLE_RATE = 16000;
  const BUFFER_SIZE = 1024;

  let mediaStream = null;
  let audioContext = null;
  let sourceNode = null;
  let processorNode = null;
  let running = false;

  function closeAudioContext() {
    if (processorNode) {
      try {
        processorNode.disconnect();
      } catch (_) {}
      processorNode.onaudioprocess = null;
      processorNode = null;
    }
    if (sourceNode) {
      try {
        sourceNode.disconnect();
      } catch (_) {}
      sourceNode = null;
    }
    if (audioContext) {
      try {
        audioContext.close();
      } catch (_) {}
      audioContext = null;
    }
  }

  function stopStream() {
    if (mediaStream) {
      mediaStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (_) {}
      });
      mediaStream = null;
    }
  }

  function stopAll() {
    running = false;
    closeAudioContext();
    stopStream();
  }

  async function openStream() {
    if (!navigator || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error('getUserMedia is not supported in this browser.');
    }
    return navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: TARGET_SAMPLE_RATE,
        channelCount: 1,
        noiseSuppression: true,
        echoCancellation: true,
        autoGainControl: true,
      },
      video: false,
    });
  }

  function floatTo16BitPCM(float32Array) {
    const buffer = new ArrayBuffer(float32Array.length * 2);
    const view = new DataView(buffer);
    for (let i = 0; i < float32Array.length; i++) {
      let s = Math.max(-1, Math.min(1, float32Array[i]));
      // eslint-disable-next-line no-nested-ternary
      s = s < 0 ? s * 0x8000 : s * 0x7fff;
      view.setInt16(i * 2, s, true);
    }
    return new Uint8Array(buffer);
  }

  function resampleFloat32(buffer, fromRate, toRate) {
    if (fromRate === toRate) {
      return buffer;
    }
    const ratio = fromRate / toRate;
    const newLength = Math.round(buffer.length / ratio);
    const resampled = new Float32Array(newLength);
    for (let i = 0; i < newLength; i++) {
      const origin = i * ratio;
      const lower = Math.floor(origin);
      const upper = Math.ceil(origin);
      if (upper >= buffer.length) {
        resampled[i] = buffer[buffer.length - 1];
      } else if (lower === upper) {
        resampled[i] = buffer[lower];
      } else {
        const weight = origin - lower;
        resampled[i] = (1 - weight) * buffer[lower] + weight * buffer[upper];
      }
    }
    return resampled;
  }

  window.MicRecorder = {
    async start(onData) {
      if (running) {
        return;
      }
      running = true;
      try {
        stopAll();
        mediaStream = await openStream();
        const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
        audioContext = new AudioContextCtor({ sampleRate: TARGET_SAMPLE_RATE });
        sourceNode = audioContext.createMediaStreamSource(mediaStream);
        processorNode = audioContext.createScriptProcessor(BUFFER_SIZE, 1, 1);

        const inputSampleRate = audioContext.sampleRate;
        const needsResample = inputSampleRate !== TARGET_SAMPLE_RATE;

        processorNode.onaudioprocess = (event) => {
          if (!running) {
            return;
          }
          let floatData = event.inputBuffer.getChannelData(0);
          if (needsResample) {
            floatData = resampleFloat32(floatData, inputSampleRate, TARGET_SAMPLE_RATE);
          }
          const bytes = floatTo16BitPCM(floatData);
          try {
            onData(bytes.buffer.slice(0));
          } catch (err) {
            console.error('MicRecorder callback error', err);
          }
        };

        sourceNode.connect(processorNode);
        processorNode.connect(audioContext.destination);
      } catch (err) {
        console.error('MicRecorder start failed', err);
        stopAll();
        throw err;
      }
    },
    stop() {
      stopAll();
    },
  };
})();
