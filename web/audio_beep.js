// Web Audio API beep sound generator
window.playBeepSound = function(frequency, durationMs) {
  try {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) {
      console.error('❌ AudioContext not available');
      return;
    }
    
    const audioContext = new AudioContext();
    
    // Play 3 beeps with gaps between them
    const playBeep = (delay) => {
      setTimeout(() => {
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        
        // Set frequency (pitch)
        oscillator.frequency.value = frequency || 800;
        oscillator.type = 'sine'; // Smooth sine wave
        
        // Set volume - increased to 85%
        gainNode.gain.value = 0.85;
        
        // Connect nodes
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        
        // Play
        oscillator.start();
        
        // Stop after duration
        setTimeout(() => {
          try {
            oscillator.stop();
          } catch (e) {
            // Ignore stop errors
          }
        }, 250);
      }, delay);
    };
    
    // Play 3 beeps with more spacing: at 0ms, 800ms, and 1600ms
    playBeep(0);
    playBeep(800);
    playBeep(1600);
    
  } catch (e) {
    console.error('❌ Error playing beep:', e);
  }
};
