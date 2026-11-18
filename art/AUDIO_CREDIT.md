# Audio

The push, goal and completion effects are original procedural synthesis in `audio_service.gd`: a damped low tone/noise, a two-tone chime, and a three-note completion sound. No external recordings, samples, music or third-party sound libraries are bundled.

The volume is deliberately modest. M or the visible sound button toggles the game effects; mute stops current voices immediately. Since V7.11 the effect volume and mute are saved between launches (user://settings.cfg).

Menu UI experiment build: one background music track is included, "Forget Me Not" (looped version) by Kistol, CC0, from OpenGameArt. Source, licence evidence and details are in `music/AUDIO_CREDIT.md`. Music has its own toggle and volume on the main menu, saved separately (user://music_settings.cfg); M still controls only the effects.

Browsers may suppress sound until the first user interaction. Headless automated tests verify PCM structure, routing and mute behavior, not perceived loudness on the user's speakers.
