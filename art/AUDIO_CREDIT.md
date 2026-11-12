# Audio

The push, goal and completion effects are original procedural synthesis in `audio_service.gd`: a damped low tone/noise, a two-tone chime, and a three-note completion sound. No external recordings, samples, music or third-party sound libraries are bundled.

The volume is deliberately modest. M or the visible sound button toggles all game effects; mute stops current voices immediately. The setting persists across scenes during the current run, but resets when launching the game again. No background music is included.

Browsers may suppress sound until the first user interaction. Headless automated tests verify PCM structure, routing and mute behavior, not perceived loudness on the user's speakers.
