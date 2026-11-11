Put your audio files (mp3, wav, m4a, aif, caf) in this folder, then rebuild.

- Every file is discovered automatically. The game analyses BPM, downbeat and the drop
  section on first launch and caches the result.
- tracks.json is optional per file: title, artist, genre, license, cleared, and manual
  overrides (bpm, dropStart, dropEnd in seconds) if the analyser picks the wrong section.
- Debug builds play every file. Release builds only play files with "cleared": true.
  Only set it after confirming the license allows use in a commercial game and editing.
- Override example: {"file": "MyTrack.wav", "bpm": 124, "dropStart": 61.9, "dropEnd": 92.9}
