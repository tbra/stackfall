# Owner-created theme music

These tracks were supplied by the owner from Suno on 2026-09-27 and converted
from M4A/Opus to 192 kbps stereo MP3 for Godot playback.

| Bundled file | Source in `feedback/audio` | Playlist |
| --- | --- | --- |
| `menu-theme.mp3` | `menu-theme [usesuno.com].m4a` | Menu and lobby |
| `lobby-theme.mp3` | `menu-theme [usesuno.com] (1).m4a` | Menu and lobby |
| `stacking-blocks.mp3` | `stacking-blocks [usesuno.com].m4a` | Gameplay |
| `stacking-blocks-2.mp3` | `stacking-blocks [usesuno.com] (1).m4a` | Gameplay |
| `stacking-blocks-3.mp3` | `stacking-blocks [usesuno.com] (2).m4a` | Gameplay |

Playlist membership and fade/gap durations live in `config/audio_config.tres`
and `config/AudioConfig.gd`. Tracks play once, not on a continuous loop.
Custom music folders and capture-intensity stems are temporarily disabled.
Menu and lobby share both tracks without restarting music on navigation.
The first gameplay track is the earlier owner-supplied theme, included only once.

To convert a replacement with a recent FFmpeg:

```powershell
ffmpeg -nostdin -n -i 'source.m4a' -vn -c:a libmp3lame -b:a 192k 'destination.mp3'
```

Use the original source rather than transcoding an existing MP3. Import the
new file in Godot before exporting. Original Bontago sound effects remain
separate, optional local assets; these files do not replace those effects.
