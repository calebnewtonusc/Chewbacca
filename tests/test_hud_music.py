#!/usr/bin/env python3
"""bin/hud-music, with no player and no network.

The words are the part that has to be right for the voice: "play drake" is
an artist, "play blinding lights" is a song, "skip" is a skip and "play" is a
resume. Every player is stubbed, so nothing here makes a sound.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bin" / "hud-music"

failures = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failures
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures += 1


def load(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


def track(name: str, artist: str, uri: str) -> dict:
    return {"name": name, "uri": uri, "artists": [{"name": artist}]}


def results(tracks=(), artists=(), albums=()) -> dict:
    return {
        "tracks": {"items": list(tracks)},
        "artists": {"items": [{"name": n, "uri": u} for n, u in artists]},
        "albums": {"items": [{"name": n, "uri": u, "artists": [{"name": a}]} for n, u, a in albums]},
    }


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        bob = Path(tmp) / "bob"
        bob.mkdir()
        os.environ["BOB_DIR"] = str(bob)
        os.environ.pop("SPOTIFY_CLIENT_ID", None)
        os.environ.pop("SPOTIFY_CLIENT_SECRET", None)
        music = load("hud_music_under_test", TOOL)

        print("the words")
        cases = {
            "play blinding lights": ("play", "blinding lights", ""),
            "Play Blinding Lights by The Weeknd, please": ("play", "blinding lights by the weeknd", ""),
            "hey can you put on some drake": ("play", "drake", ""),
            "play something by drake": ("play", "drake", "artist"),
            "play songs by the weeknd on spotify": ("play", "the weeknd", "artist"),
            "play the album blonde": ("play", "blonde", "album"),
            "play the song hotline bling": ("play", "hotline bling", ""),
            "i want to hear hotel california": ("play", "hotel california", ""),
            "Open Spotify and play some Fred again": ("play", "fred again", ""),
            # Said to the voice on 2026-09-20; the model spent 175 s and 29 tools on it.
            "Also play Fred again while we work": ("play", "fred again", ""),
            "play hotel california for a bit please": ("play", "hotel california", ""),
            "play me and my broken heart": ("play", "me and my broken heart", ""),
            "play some music": ("resume", "", ""),
            "play": ("resume", "", ""),
            "resume": ("resume", "", ""),
            "keep playing": ("resume", "", ""),
            "pause": ("pause", "", ""),
            "pause the music": ("pause", "", ""),
            "skip": ("next", "", ""),
            "skip this song": ("next", "", ""),
            "next song": ("next", "", ""),
            "go back a song": ("previous", "", ""),
            "play that again": ("again", "", ""),
            "stop the music": ("stop", "", ""),
            "turn the music off": ("stop", "", ""),
            "what's playing": ("now", "", ""),
            "what song is this": ("now", "", ""),
            "who sings this": ("now", "", ""),
        }
        for said, (verb, what, want) in cases.items():
            command = music.parse(said)
            got = (command.verb, command.what, command.want) if command else None
            check(f"{said!r} is {verb}" + (f" {what!r}" if what else ""), got == (verb, what, want), str(got))
        for said, level in {"turn it up": "up", "louder": "up", "quieter": "down", "volume down": "down",
                            "set the volume to 40": "40", "volume 300": "100", "make it way down": "down"}.items():
            command = music.parse(said)
            check(f"{said!r} is volume {level}", command is not None and command.verb == "volume" and command.level == level,
                  str(command))
        for said in ("what's due tomorrow", "play the voicemail", "text caleb i'm running late", "stop", "", "playing with fire is bad",
                     "play some jazz and tell me the time", "play drake and then remind me at 5"):
            command = music.parse(said)
            if said == "play the voicemail":
                # Words after play are a search; the bridge finds nothing and says so.
                check("'play the voicemail' is still a play", command is not None and command.verb == "play")
            else:
                check(f"{said!r} is not music", command is None, str(command))
        check("a query drops the by", music.Command("play", what="blinding lights by the weeknd").query == "blinding lights the weeknd")

        print("choosing")
        found = results(
            tracks=[track("Blinding Lights", "The Weeknd", "spotify:track:bl"), track("Drake", "Someone Else", "spotify:track:dr")],
            artists=[("The Weeknd", "spotify:artist:tw"), ("Drake", "spotify:artist:dk")],
            albums=[("After Hours", "spotify:album:ah", "The Weeknd")],
        )
        pick = music.choose("blinding lights", found)
        check("a song title is the song", pick and pick.uri == "spotify:track:bl" and pick.title == "Blinding Lights by The Weeknd", str(pick))
        pick = music.choose("drake", found)
        check("an artist's name is the artist, even with a song of that name", pick and pick.uri == "spotify:artist:dk", str(pick))
        pick = music.choose("weeknd", found)
        check("the artist without its the", pick and pick.uri == "spotify:artist:tw", str(pick))
        pick = music.choose("blinding lights the weeknd", found)
        check("song and artist together is the song", pick and pick.kind == "track", str(pick))
        pick = music.choose("anything", found, want="album")
        check("album when asked", pick and pick.uri == "spotify:album:ah" and pick.title.startswith("the album After Hours"), str(pick))
        pick = music.choose("anything", found, want="artist")
        check("artist when asked", pick and pick.uri == "spotify:artist:tw", str(pick))
        check("nothing from nothing", music.choose("x", results()) is None)
        check("a youtube title reads as song by artist",
              music.tidy_title("The Weeknd - Blinding Lights (Official Video)") == "Blinding Lights by The Weeknd"
              and music.tidy_title("Hotel California [Official Audio] | Eagles") == "Hotel California")

        print("playing, with every player stubbed")
        calls: list[str] = []
        state = {"spotify": "stopped", "music": "off", "keys": None, "youtube": None, "apps": {"Spotify"}}
        music.running = lambda app: app in state["apps"]
        music.spotify_keys = lambda: state["keys"]
        music.spotify_state = lambda: state["spotify"]
        music.music_state = lambda: state["music"]
        music.spotify_now = lambda: "Blinding Lights by The Weeknd"
        music.spotify_search = lambda query: (calls.append(f"search {query}"), found)[1]
        music.spotify_tell = lambda script: (calls.append(f"spotify {script}"), "66")[1]
        music.osascript = lambda script, timeout=8: (calls.append(f"osa {script[:40]}"), "63")[1]
        music.youtube_lookup = lambda query: (calls.append(f"youtube {query}"), ("The Weeknd - Blinding Lights (Official Video)", "https://audio"))[1]
        music.spawn_player = lambda url: (calls.append(f"ffplay {url}"), 4242)[1]
        music.youtube_alive = lambda: state["youtube"]
        music.stop_youtube = lambda: (calls.append("stop youtube"), False)[1]
        music.youtube_ready = lambda: True
        music.system_volume = lambda: 63
        music.SPOTIFY_APP = Path(tmp) / "Spotify.app"

        out = music.perform(music.parse("play blinding lights"))
        check("no keys: YouTube plays it and says so",
              out.ok and out.line == "Playing Blinding Lights by The Weeknd, from YouTube." and calls == ["youtube blinding lights", "stop youtube", "ffplay https://audio"],
              f"{out} {calls}")
        check("the YouTube player is remembered", json.loads((bob / "music-youtube.json").read_text())["pid"] == 4242)
        calls.clear()
        state["keys"] = {"client_id": "id", "client_secret": "secret"}
        out = music.perform(music.parse("play blinding lights by the weeknd"))
        check("with keys: Spotify searches once and plays the URI",
              out.ok and out.line == "Playing Blinding Lights by The Weeknd." and calls == ["search blinding lights the weeknd", "stop youtube", 'spotify play track "spotify:track:bl"'],
              f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play something by drake"))
        check("an artist plays the artist", out.ok and out.line == "Playing Drake." and 'spotify play track "spotify:artist:dk"' in calls, f"{out} {calls}")
        calls.clear()
        music.spotify_search = lambda query: results()
        out = music.perform(music.parse("play quarterly report"))
        check("nothing on Spotify falls through to YouTube", out.ok and "from YouTube" in out.line and "youtube quarterly report" in calls, f"{out} {calls}")
        music.youtube_lookup = lambda query: (_ for _ in ()).throw(music.PlayerError(f"YouTube had nothing for {query}"))
        out = music.perform(music.parse("play quarterly report"))
        check("nothing anywhere is one sentence, not ok",
              not out.ok and out.line.startswith("Couldn't play quarterly report: nothing on Spotify called quarterly report; YouTube had nothing"), out.line)

        calls.clear()
        state["spotify"] = "playing"
        check("pause goes to Spotify", music.perform(music.Command("pause")).line == "Paused." and calls == ["spotify pause"], str(calls))
        calls.clear()
        out = music.perform(music.Command("next"))
        check("next says what is next", out.ok and out.line == "Next: Blinding Lights by The Weeknd." and calls == ["spotify next track"], f"{out} {calls}")
        calls.clear()
        out = music.perform(music.Command("volume", level="up"))
        check("louder is a step up on Spotify", out.line == "Volume 81." and calls == ["spotify sound volume", "spotify set sound volume to 81"], f"{out} {calls}")
        out = music.perform(music.Command("volume", level="40"))
        check("a number is the number", out.line == "Volume 40.")
        check("now says the song and the player", music.perform(music.Command("now")).line == "Blinding Lights by The Weeknd, on Spotify.")
        calls.clear()
        out = music.perform(music.Command("stop"))
        check("stop pauses Spotify and says music off", out.ok and out.line == "Music off." and calls == ["stop youtube", "spotify pause"], f"{out} {calls}")
        state["spotify"] = "stopped"
        check("nothing playing is said plainly", music.perform(music.Command("pause")).line == "Nothing's playing." and music.active_player() is None)
        state["youtube"] = {"pid": 4242, "title": "The Weeknd - Blinding Lights (Official Video)", "paused": False}
        check("a YouTube single has no next", not music.perform(music.Command("next")).ok)
        check("now from YouTube", music.perform(music.Command("now")).line == "Blinding Lights by The Weeknd, from YouTube.")
        calls.clear()
        out = music.perform(music.Command("volume", level="down"))
        check("volume with YouTube is the Mac's", out.line == "Volume 48." and calls == ["osa set volume output volume 48"], f"{out} {calls}")

        print("the command")
        env = dict(os.environ)
        run = lambda *args: subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env)  # noqa: E731
        out = run("parse", "play some drake")
        check("parse prints the command as JSON", out.returncode == 0 and json.loads(out.stdout)["what"] == "drake", out.stdout + out.stderr)
        check("parse of anything else is exit 1", run("parse", "what time is it").returncode == 1)
        out = run("status")
        check("status names every player", out.returncode == 0 and "Spotify" in out.stdout and "YouTube" in out.stdout and "Music.app" in out.stdout, out.stdout + out.stderr)
        out = run("setup", "abc", "def")
        keys = json.loads((bob / "spotify.json").read_text())
        check("setup saves the keys read-only to the owner",
              keys == {"client_id": "abc", "client_secret": "def", "market": "US"} and oct((bob / "spotify.json").stat().st_mode)[-3:] == "600"
              and "saved" in out.stdout, out.stdout + out.stderr)

    print("\nall passed" if not failures else f"\n{failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
