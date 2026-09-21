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


# Spotify's search page on 2026-09-20, trimmed to the tags that are read.
HERO_TRACK = (
    '<div aria-live="polite" data-testid="top-result-card"><div><div draggable="true"><div><img alt=""></div><div>'
    '<a draggable="false" title="Hotel California - 2013 Remaster" dir="auto" href="/track/40riOy7x9W7GXjyGp4pjAv">'
    '<div data-encore-id="text">Hotel California - 2013 Remaster</div></a><div data-encore-id="text"><span data-encore-id="text">Song</span>'
    '<span data-encore-id="text"><a draggable="true" dir="auto" href="/artist/0ECwFtbIWEVNwjlrfc6xoL">Eagles</a></span></div></div>'
    '<button data-testid="play-button" aria-label="Play"></button></div></div></div>')
HERO_ARTIST = (
    '<div data-testid="top-result-card"><div><a draggable="false" title="Fred again.." dir="auto" href="/artist/4oLeXFyACqeem2VImYeBFe">'
    '<div data-encore-id="text">Fred again..</div></a><div><span data-encore-id="text">Artist</span></div></div></div>')
HERO_ALBUM = (
    '<div data-testid="top-result-card"><div><a draggable="false" title="Blonde" href="/album/3mH6qwIy9crq0I9YQbOuDf"><div>Blonde</div></a>'
    '<span data-encore-id="text">Album</span><span><a draggable="true" href="/artist/2h93pZq0e7k5yf4dywlkpM">Frank Ocean</a></span></div></div>')
HERO_PLAYLIST = (
    '<div data-testid="top-result-card"><div><a draggable="false" title="Something chill" href="/playlist/2DS9f2LPCPXriE16flYJxR"><div>Something chill</div></a>'
    '<span data-encore-id="text">Playlist</span><span><a draggable="false" href="/user/1290960422">Ryan Blakewood</a></span></div></div>')
HERO_EPISODE = (
    '<div data-testid="top-result-card"><div><a draggable="false" title="Written In Your Heart (from &#x201C;Barbie&#x201D;)" href="/episode/6RwSh089NqZLdg8jMcTRYG">'
    '<div>Written In Your Heart</div></a><span data-encore-id="text">Episode</span></div></div>')
VIDEO_TRACK = (
    '<div aria-live="polite" data-testid="top-result-card"><div title="New Freezer (feat. Kendrick Lamar)">'
    '<div data-encore-id="card" role="group" aria-labelledby="card-title-spotify:track:2EgB4n6XyBsuNUbuarr4eG" data-video-preview-card="true">'
    '<div role="button" aria-labelledby="card-title-spotify:track:2EgB4n6XyBsuNUbuarr4eG card-subtitle-spotify:track:2EgB4n6XyBsuNUbuarr4eG"></div>'
    '<img data-testid="video-card-image" alt=""><p data-encore-id="cardTitle" id="card-title-spotify:track:2EgB4n6XyBsuNUbuarr4eG" dir="auto">'
    '<span>New Freezer (feat. Kendrick Lamar)</span></p><div data-encore-id="cardSubtitle"><span><a draggable="true" href="/artist/1pPmIToKXyGdsCF6LmqLmI">Rich The Kid</a>, '
    '<a draggable="true" href="/artist/2YZyLoL8N0Wb9xBt1NhZWg">Kendrick Lamar</a></span></div>'
    '<button data-testid="more-button" aria-label="More options for New Freezer (feat. Kendrick Lamar)"></button></div></div></div>')
SONG_ROW = (
    '<div data-testid="tracklist-row" draggable="true" role="presentation"><div role="gridcell"><img alt="">'
    '<button aria-label="Play Barbie World (with Aqua) [From Barbie The Album] by Nicki Minaj, Ice Spice, Aqua"></button></div><div>'
    '<a draggable="false" href="/track/741UUVE2kuITl0c6zuqqbO" tabindex="-1"><div data-encore-id="text" dir="auto">Barbie World (with Aqua) [From Barbie The Album]</div></a>'
    '<span data-encore-id="text"><span role="img" aria-label="Explicit" data-encore-id="tagIcon" title="Explicit">E</span></span>'
    '<span><a draggable="true" href="/artist/0hCNtLu0JehylgoiP8L4Gh">Nicki Minaj</a>, <a href="/artist/3LZZPxNDGDFVSIPqf4JuEf">Ice Spice</a></span></div></div>')


def track(name: str, artist: str, uri: str) -> dict:
    return {"name": name, "uri": uri, "artists": [{"name": artist}]}


def results(tracks=(), artists=(), albums=()) -> dict:
    return {
        "tracks": {"items": list(tracks)},
        # Drake and the Weeknd have a following; an artist called Blinding Lights does not.
        "artists": {"items": [{"name": n, "uri": u, "followers": {"total": 0 if n == "Blinding Lights" else 5_000_000}} for n, u in artists]},
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
            "Play some Mac DeMarco on Spotify while I work": ("play", "mac demarco", ""),
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
            # Said at 15:10 on 2026-09-20; the model spent 64 s on it.
            "Shuffle the album here comes the cowboy by Mac DeMarco": ("play", "here comes the cowboy by mac demarco", "album"),
            "play mac demarco on shuffle": ("play", "mac demarco", ""),
            "shuffle fred again": ("play", "fred again", ""),
            "shuffle": ("shuffle", "", ""),
            "shuffle it": ("shuffle", "", ""),
            "put it on shuffle": ("shuffle", "", ""),
            "turn off shuffle": ("shuffle", "", ""),
            "shuffle the music": ("shuffle", "", ""),
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
        for said, shuffle in {"shuffle the album blonde": "on", "play blonde on shuffle": "on", "play blonde shuffled": "on", "play blonde": "",
                              "shuffle": "on", "turn off shuffle": "off", "shuffle off": "off", "stop shuffling": "off", "turn shuffle on": "on"}.items():
            command = music.parse(said)
            level = command.shuffle if command.verb == "play" else command.level
            check(f"{said!r} shuffle is {shuffle or 'not said'}", level == shuffle, str(command))
        for said, what in {"play something chill": "chill", "play the new kendrick": "the new kendrick", "play that song from barbie": "that song from barbie"}.items():
            command = music.parse(said)
            check(f"{said!r} is a search like any other", command is not None and command.verb == "play" and command.what == what, str(command))
        for said, platform in {"play mac demarco on spotify": "spotify", "play hotel california on youtube": "youtube",
                               "play hotel california in apple music": "music", "play hotel california": ""}.items():
            command = music.parse(said)
            check(f"{said!r} says where: {platform or 'nowhere'}", command is not None and command.platform == platform, str(command))

        print("choosing")
        found = results(
            tracks=[track("Blinding Lights", "The Weeknd", "spotify:track:bl"), track("Drake", "Someone Else", "spotify:track:dr")],
            artists=[("The Weeknd", "spotify:artist:tw"), ("Drake", "spotify:artist:dk"), ("Blinding Lights", "spotify:artist:bl")],
            albums=[("After Hours", "spotify:album:ah", "The Weeknd")],
        )
        pick = music.choose("blinding lights", found)
        check("a song title is the song, even with an unknown artist of that name", pick and pick.uri == "spotify:track:bl" and pick.title == "Blinding Lights by The Weeknd", str(pick))
        pick = music.choose("drake", found)
        check("an artist's name is the artist, even with a song of that name", pick and pick.uri == "spotify:artist:dk", str(pick))
        pick = music.choose("weeknd", found)
        check("the artist without its the", pick and pick.uri == "spotify:artist:tw", str(pick))
        pick = music.choose("blinding lights the weeknd", found)
        check("song and artist together is the song", pick and pick.kind == "track", str(pick))
        pick = music.choose("after hours", found, want="album")
        check("album when asked", pick and pick.uri == "spotify:album:ah" and pick.title.startswith("the album After Hours"), str(pick))
        pick = music.choose("weeknd", found, want="artist")
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
        music.spotify_open_search = lambda what: (calls.append(f"open spotify search {what}"), music.Outcome(True, f"Opened {what} in Spotify. Tap the top result to play it.", music.SETUP_NOTE))[1]
        # No browser first: the open sources are what is left.
        music.spotify_web_read = lambda query: (_ for _ in ()).throw(music.PlayerError("no browser to read Spotify's search with"))
        # The open sources, stubbed: Deezer names the thing, Wikidata or
        # MusicBrainz knows its Spotify ID.
        deezer = {
            "blinding lights": ([{"title": "Blinding Lights", "artist": {"name": "The Weeknd"}}], [{"name": "Blinding Lights", "nb_fan": 12}]),
            "mac demarco": ([{"title": "Chamber Of Reflection", "artist": {"name": "Mac DeMarco"}}], [{"name": "Mac DeMarco", "nb_fan": 900_000}]),
            "fred again": ([{"title": "Marea", "artist": {"name": "Fred again.."}}], [{"name": "Fred again..", "nb_fan": 400_000}]),
            "marea fred again": ([{"title": "Marea (We've Lost Dancing)", "artist": {"name": "Fred again.."}}], [{"name": "Fred again..", "nb_fan": 400_000}]),
            "quarterly report": ([], []),
            "freddie again": ([{"title": "Begin Again", "artist": {"name": "Freddie And The Scenarios"}}], [{"name": "Freddie Gibbs", "nb_fan": 90_000}]),
            "hotel california": ([{"title": "Hotel California (2013 Remaster)", "artist": {"name": "Eagles"}, "album": {"title": "Hotel California"}}], [{"name": "Eagles", "nb_fan": 3_000_000}]),
            "wasted times": ([{"title": "Wasted Times", "artist": {"name": "The Weeknd"}, "album": {"title": "My Dear Melancholy,"}}], []),
        }
        music.deezer_tracks = lambda q: (calls.append(f"deezer tracks {q}"), deezer.get(q, ([], []))[0])[1]
        music.deezer_artists = lambda q: (calls.append(f"deezer artists {q}"), deezer.get(q, ([], []))[1])[1]
        wikidata = {("Blinding Lights", "P2207"): "0VjIjW4GlUZAMYd2vXMi3b", ("Mac DeMarco", "P1902"): "3Sz7ZnJQBIHsXLUSo0OQtM",
                    ("Begin Again", "P2207"): "ba22",
                    ("Marea", "P2207"): "marea22", ("Eagles", "P1902"): "0ECwFtbIWEVNwjlrfc6xoL", ("The Weeknd", "P1902"): "1Xyo4u8uXC1ZmMpatF05PJ",
                    ("My Dear Melancholy,", "P2205"): "mdm"}
        embeds = {("artist", "0ECwFtbIWEVNwjlrfc6xoL"): [("Take It Easy - 2013 Remaster", "spotify:track:tie"), ("Hotel California - 2013 Remaster", "spotify:track:hc")],
                  ("artist", "1Xyo4u8uXC1ZmMpatF05PJ"): [("Blinding Lights", "spotify:track:0VjIjW4GlUZAMYd2vXMi3b")],
                  ("album", "mdm"): [("Call Out My Name", "spotify:track:comn"), ("Wasted Times", "spotify:track:wt")]}
        music.spotify_embed_tracks = lambda kind, sid: (calls.append(f"embed {kind} {sid}"), embeds.get((kind, sid), []))[1]
        music.wikidata_spotify_id = lambda text, prop, mention="": (calls.append(f"wikidata {prop} {text}"), wikidata.get((text, prop)))[1]
        music.musicbrainz_artist_spotify_id = lambda name: (calls.append(f"musicbrainz {name}"), {"Fred again..": "4oLeXFyACqeem2VImYeBFe"}.get(name))[1]

        out = music.perform(music.parse("play marea fred again"))
        check("a title with a parenthetical is looked up bare as well",
              out.ok and out.line == "Playing Marea (We've Lost Dancing) by Fred again.." and "wikidata P2207 Marea" in calls
              and 'spotify play track "spotify:track:marea22"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play hotel california"))
        check("a song Wikidata lacks is found on the artist's own page",
              out.ok and out.line == "Playing Hotel California - 2013 Remaster by Eagles." and 'spotify play track "spotify:track:hc"' in calls
              and "embed artist 0ECwFtbIWEVNwjlrfc6xoL" in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play wasted times"))
        check("a song off the top ten is found on its album's page",
              out.ok and out.line == "Playing Wasted Times by The Weeknd." and 'spotify play track "spotify:track:wt"' in calls
              and "embed album mdm" in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play blinding lights"))
        check("no keys: a song is found through Deezer and Wikidata and plays on Spotify",
              out.ok and out.line == "Playing Blinding Lights by The Weeknd." and 'spotify play track "spotify:track:0VjIjW4GlUZAMYd2vXMi3b"' in calls
              and "wikidata P2207 Blinding Lights" in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play some mac demarco on spotify"))
        check("no keys: an artist plays the artist", out.ok and out.line == "Playing Mac DeMarco." and 'spotify play track "spotify:artist:3Sz7ZnJQBIHsXLUSo0OQtM"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play fred again"))
        check("no keys: MusicBrainz when Wikidata has no ID", out.ok and out.line == "Playing Fred again.." and 'spotify play track "spotify:artist:4oLeXFyACqeem2VImYeBFe"' in calls
              and "musicbrainz Fred again.." in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play mac demarco"))
        check("the second time is from the cache, no lookups", out.ok and out.line == "Playing Mac DeMarco." and not any(c.startswith(("deezer", "wikidata", "musicbrainz")) for c in calls), str(calls))
        calls.clear()
        out = music.perform(music.parse("play quarterly report"))
        check("no keys, never heard of it: Spotify opens with the search, and the note says how to set it up",
              out.ok and out.unsure and out.line.endswith("Opened quarterly report in Spotify. Tap the top result to play it.") and "open spotify search quarterly report" in calls
              and "hud-music setup" in out.note, f"{out} {calls}")
        calls.clear()
        command = music.parse("play freddie again")
        command.quiet_miss = True
        out = music.perform(command)
        check("a weak guess is not pressed play on: unsure, nothing opened, nothing played",
              not out.ok and out.unsure and out.line == "Not sure what freddie again is." and not any("spotify play" in c or "open spotify" in c for c in calls), f"{out} {calls}")
        calls.clear()
        command = music.parse("play freddie again")
        command.anyway = True
        out = music.perform(command)
        check("--anyway plays the best guess", out.ok and out.line == "Playing Begin Again by Freddie And The Scenarios." and 'spotify play track "spotify:track:ba22"' in calls, f"{out} {calls}")
        calls.clear()

        print("Spotify's own top result")
        fields = music.card_fields(HERO_TRACK)
        check("a hero card: the titled link, and who it is by",
              fields == ("spotify:track:40riOy7x9W7GXjyGp4pjAv", "Hotel California - 2013 Remaster", ["Eagles"]), str(fields))
        fields = music.card_fields(VIDEO_TRACK)
        check("a video card: the URI is only in its labels, the artists are links",
              fields == ("spotify:track:2EgB4n6XyBsuNUbuarr4eG", "New Freezer (feat. Kendrick Lamar)", ["Rich The Kid", "Kendrick Lamar"]), str(fields))
        fields = music.card_fields(SONG_ROW)
        check("a song row: the untitled track link, not the explicit tag's title",
              fields == ("spotify:track:741UUVE2kuITl0c6zuqqbO", "Barbie World (with Aqua) [From Barbie The Album]", ["Nicki Minaj", "Ice Spice"]), str(fields))
        fields = music.card_fields(HERO_PLAYLIST)
        check("a playlist: by its owner", fields == ("spotify:playlist:2DS9f2LPCPXriE16flYJxR", "Something chill", ["Ryan Blakewood"]), str(fields))
        check("entities are read as text", music.card_fields(HERO_TRACK.replace("Hotel California - 2013 Remaster", "Fred &amp; Co"))[1] == "Fred & Co")
        check("a card with nothing playable is nothing", music.card_fields("<div data-testid=\"top-result-card\">yb<a href=\"/user/1\">x</a></div>") is None)
        check("what is said for each kind", [music.spoken_pick(*f).title for f in (
            ("spotify:track:1", "Marea (we've lost dancing)", ["Fred again..", "The Blessed Madonna"]), ("spotify:artist:1", "Fred again..", []),
            ("spotify:album:1", "After Hours (Deluxe)", ["The Weeknd"]), ("spotify:playlist:1", "Something chill", ["Ryan"]), ("spotify:episode:1", "#2551", []))]
            == ["Marea by Fred again..", "Fred again..", "the album After Hours by The Weeknd", "the playlist Something chill", "the episode #2551"])
        pages = {"freddie again": (HERO_ARTIST, ""), "the new kendrick": (VIDEO_TRACK, SONG_ROW), "hotel california": (HERO_TRACK, ""),
                 "that song from barbie": (HERO_EPISODE, SONG_ROW), "the joe rogan podcast": (HERO_EPISODE, SONG_ROW),
                 "blonde album": (HERO_ALBUM, ""), "chill": (HERO_PLAYLIST, ""), "nothing at all": ("", "")}
        music.spotify_web_read = lambda query: (calls.append(f"web {query}"), pages[query])[1]
        out = music.perform(music.parse("play freddie again"))
        check("a misheard name plays what Spotify's search puts at the top, nothing else asked",
              out.ok and out.line == "Playing Fred again.." and calls == ["web freddie again", "stop youtube", 'spotify play track "spotify:artist:4oLeXFyACqeem2VImYeBFe"'], f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play freddie again"))
        check("the second time is from the cache", out.ok and calls == ["stop youtube", 'spotify play track "spotify:artist:4oLeXFyACqeem2VImYeBFe"'], str(calls))
        cache = json.loads((bob / "music-cache.json").read_text())
        cache["web:freddie again"]["at"] = 0
        (bob / "music-cache.json").write_text(json.dumps(cache))
        calls.clear()
        music.perform(music.parse("play freddie again"))
        check("a week on, the page is read again", calls[0] == "web freddie again", str(calls))
        calls.clear()
        out = music.perform(music.parse("play the new kendrick"))
        check("words that describe are Spotify's to answer too", out.ok and out.line == "Playing New Freezer by Rich The Kid." and 'spotify play track "spotify:track:2EgB4n6XyBsuNUbuarr4eG"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play hotel california"))
        check("the edition is not said", out.ok and out.line == "Playing Hotel California by Eagles.", f"{out}")
        calls.clear()
        out = music.perform(music.parse("play that song from barbie"))
        check("a podcast at the top of a music request gives way to the first song",
              out.ok and out.line == "Playing Barbie World by Nicki Minaj." and 'spotify play track "spotify:track:741UUVE2kuITl0c6zuqqbO"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play the joe rogan podcast"))
        check("a podcast asked for is played", out.ok and out.line.startswith("Playing the episode ") and 'spotify play track "spotify:episode:6RwSh089NqZLdg8jMcTRYG"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play the album blonde"))
        check("an album is searched with the word on the end", out.ok and out.line == "Playing the album Blonde by Frank Ocean." and calls[0] == "web blonde album", f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play something chill"))
        check("a playlist plays as one", out.ok and out.line == "Playing the playlist Something chill." and 'spotify play track "spotify:playlist:2DS9f2LPCPXriE16flYJxR"' in calls, f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("shuffle the album blonde"))
        check("shuffle turns shuffling on before the album starts",
              out.ok and out.line == "Shuffling the album Blonde by Frank Ocean." and calls[-2:] == ["spotify set shuffling to true", 'spotify play track "spotify:album:3mH6qwIy9crq0I9YQbOuDf"'], f"{out} {calls}")
        calls.clear()
        out = music.perform(music.parse("play nothing at all"))
        check("a page with nothing playable falls to the open sources, then the search on screen",
              out.ok and out.unsure and calls[0] == "web nothing at all" and "deezer tracks nothing at all" in calls and "open spotify search nothing at all" in calls, f"{out} {calls}")
        music.spotify_web_read = lambda query: (_ for _ in ()).throw(music.PlayerError("no browser to read Spotify's search with"))
        calls.clear()
        out = music.perform(music.parse("play blinding lights on youtube"))
        check("asked for YouTube: YouTube plays it, and the note says how to stop it",
              out.ok and out.line == "Playing Blinding Lights by The Weeknd, from YouTube." and calls == ["youtube blinding lights", "stop youtube", "ffplay https://audio"]
              and "stop the music" in out.note, f"{out} {calls}")
        check("the YouTube player is remembered", json.loads((bob / "music-youtube.json").read_text())["pid"] == 4242)
        calls.clear()
        state["apps"] = set()
        out = music.perform(music.parse("play blinding lights"))
        check("no Spotify at all: YouTube", out.ok and "from YouTube" in out.line and calls[0] == "youtube blinding lights", f"{out} {calls}")
        state["apps"] = {"Spotify"}
        calls.clear()
        state["keys"] = {"client_id": "id", "client_secret": "secret"}
        music.deezer_tracks = lambda q: (_ for _ in ()).throw(AssertionError("Deezer asked with keys in place"))
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
        out = music.perform(music.parse("play quarterly report on spotify"))
        check("nothing on Spotify, asked for Spotify: says so, no YouTube",
              not out.ok and out.line == "Couldn't play quarterly report on Spotify: nothing on Spotify called quarterly report.", out.line)
        music.youtube_lookup = lambda query: (_ for _ in ()).throw(music.PlayerError(f"YouTube had nothing for {query}"))
        out = music.perform(music.parse("play quarterly report"))
        check("nothing anywhere is one sentence, not ok",
              not out.ok and out.line.startswith("Couldn't play quarterly report: nothing on Spotify called quarterly report; YouTube had nothing"), out.line)

        calls.clear()
        state["spotify"] = "playing"
        check("pause goes to Spotify", music.perform(music.Command("pause")).line == "Paused." and calls == ["spotify pause"], str(calls))
        calls.clear()
        check("shuffle on its own is Spotify's switch", music.perform(music.Command("shuffle", level="on")).line == "Shuffle on." and calls == ["spotify set shuffling to true"], str(calls))
        calls.clear()
        check("and off", music.perform(music.Command("shuffle", level="off")).line == "Shuffle off." and calls == ["spotify set shuffling to false"], str(calls))
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
