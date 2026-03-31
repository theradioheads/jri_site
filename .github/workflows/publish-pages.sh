#!/bin/bash

# GitHub Pages Publisher & Optimizer Script for Jri Radio
# Builds site metadata and generates GitHub Pages HTML

set -e

echo "Jri Radio -- GitHub Pages Publisher"

# Configuration
SITE_DIR="site"
FILECOUNT_FILE="$SITE_DIR/filecount.txt"
FILEDATA_FILE="$SITE_DIR/filedata.txt"
DATE_FILE="$SITE_DIR/date.txt"
RADIO_FILE="$SITE_DIR/index.html"
PLAYER_FILE="$SITE_DIR/player.html"

mkdir -p "$SITE_DIR"

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
check_dependencies() {
    echo "Checking dependencies..."

    if ! command -v ffprobe &> /dev/null; then
        echo "ffprobe not found. Installing ffmpeg..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y ffmpeg
        elif command -v yum &> /dev/null; then
            sudo yum install -y ffmpeg
        else
            echo "Cannot install ffmpeg automatically. Please install it manually."
            exit 1
        fi
    fi

    echo "Dependencies OK"
}

# ---------------------------------------------------------------------------
# Count .jlres3 files
# ---------------------------------------------------------------------------
count_files() {
    echo "Counting .jlres3 files..."
    local count
    count=$(find . -name "*.jlres3" -type f | wc -l | tr -d ' ')
    echo "$count" > "$FILECOUNT_FILE"
    echo "Found $count .jlres3 files"
}

# ---------------------------------------------------------------------------
# Extract cover art as base64 -- uses -map 0:v:0 for reliable ID3 art
# ---------------------------------------------------------------------------
extract_image_base64() {
    local audio_file="$1"
    local temp_image="/tmp/cover_$$.jpg"

    if ffmpeg -i "$audio_file" -an -map 0:v:0 -vcodec copy "$temp_image" -y 2>/dev/null; then
        local base64_data
        base64_data=$(base64 -w 0 "$temp_image" 2>/dev/null || base64 "$temp_image" 2>/dev/null)
        rm -f "$temp_image"
        echo "data:image/jpeg;base64,$base64_data"
    else
        rm -f "$temp_image"
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Extract metadata
# ---------------------------------------------------------------------------
extract_metadata() {
    echo "Extracting metadata from .jlres3 files..."

    > "$FILEDATA_FILE"

    local processed=0
    local total
    total=$(cat "$FILECOUNT_FILE")

    while IFS= read -r -d '' jlres3_file; do
        processed=$((processed + 1))
        echo "Processing ($processed/$total): $(basename "$jlres3_file")"

        local temp_mp3="${jlres3_file}.mp3"
        cp "$jlres3_file" "$temp_mp3"

        local title artist img_data

        title=$(ffprobe -v quiet -show_entries format_tags=title \
            -of default=noprint_wrappers=1:nokey=1 "$temp_mp3" 2>/dev/null \
            | head -1 | tr -d '\n\r' | sed 's/=/_EQUAL_/g')
        [ -z "$title" ] && title=$(basename "$jlres3_file" .jlres3)

        artist=$(ffprobe -v quiet -show_entries format_tags=artist \
            -of default=noprint_wrappers=1:nokey=1 "$temp_mp3" 2>/dev/null \
            | head -1 | tr -d '\n\r' | sed 's/=/_EQUAL_/g')
        [ -z "$artist" ] && artist="Unknown Artist"

        img_data=$(extract_image_base64 "$temp_mp3")
        [ -z "$img_data" ] && img_data="none"

        rm -f "$temp_mp3"

        # Format: (filename|||title|||artist|||imgdata)
        # Uses ||| as delimiter to avoid collisions with base64 = padding
        echo "($(basename "$jlres3_file")|||${title}|||${artist}|||${img_data})" >> "$FILEDATA_FILE"

    done < <(find . -name "*.jlres3" -type f -print0)

    echo "Metadata extraction complete"
}

# ---------------------------------------------------------------------------
# Commit date
# ---------------------------------------------------------------------------
get_commit_date() {
    echo "Getting commit date..."
    local commit_date
    commit_date=$(git log -1 --format="%cI" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$commit_date" > "$DATE_FILE"
    echo "Commit date: $commit_date"
}

# ---------------------------------------------------------------------------
# index.html -- Radio interface
# ---------------------------------------------------------------------------
create_radio_html() {
    echo "Creating index.html (Radio)..."

    cat > "$RADIO_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jri Radio</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg:          #0a0a0c;
            --surface:     #111116;
            --surface-2:   #18181f;
            --border:      #222230;
            --border-2:    #2e2e40;
            --text:        #e8e8f0;
            --text-2:      #8888a0;
            --text-3:      #55556a;
            --accent:      #3b82f6;
            --accent-dim:  #1e3a5f;
            --accent-glow: rgba(59,130,246,0.15);
            --green:       #22c55e;
            --green-dim:   #14532d;
            --progress-bg: #1a1a24;
            --font-mono:   'IBM Plex Mono', monospace;
            --font-sans:   'IBM Plex Sans', sans-serif;
        }

        body.light {
            --bg:          #f4f4f8;
            --surface:     #ffffff;
            --surface-2:   #f0f0f5;
            --border:      #dddde8;
            --border-2:    #cbcbd8;
            --text:        #111118;
            --text-2:      #5a5a70;
            --text-3:      #9090a8;
            --accent:      #2563eb;
            --accent-dim:  #dbeafe;
            --accent-glow: rgba(37,99,235,0.08);
            --green:       #16a34a;
            --green-dim:   #dcfce7;
            --progress-bg: #e8e8f0;
        }

        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: var(--font-sans);
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            transition: background 0.2s, color 0.2s;
        }

        /* Layout */
        .shell {
            max-width: 780px;
            margin: 0 auto;
            padding: 32px 24px;
        }

        /* Header */
        .header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border);
        }

        .wordmark {
            font-family: var(--font-mono);
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.12em;
            text-transform: uppercase;
            color: var(--text-2);
        }

        .wordmark span {
            color: var(--accent);
        }

        .header-right {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .btn-ghost {
            background: none;
            border: 1px solid var(--border-2);
            color: var(--text-2);
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            transition: border-color 0.15s, color 0.15s, background 0.15s;
        }

        .btn-ghost:hover {
            border-color: var(--accent);
            color: var(--accent);
            background: var(--accent-glow);
        }

        /* Card */
        .card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 6px;
            margin-bottom: 12px;
            transition: border-color 0.2s;
        }

        /* Artist filter panel */
        .filter-panel {
            display: none;
            padding: 20px;
            border-bottom: 1px solid var(--border);
        }

        .filter-panel.open {
            display: block;
        }

        .filter-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 14px;
        }

        .filter-label {
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 600;
            letter-spacing: 0.1em;
            text-transform: uppercase;
            color: var(--text-3);
        }

        .filter-count {
            font-family: var(--font-mono);
            font-size: 11px;
            color: var(--accent);
        }

        .filter-actions {
            display: flex;
            gap: 6px;
            margin-bottom: 14px;
        }

        .btn-micro {
            background: var(--surface-2);
            border: 1px solid var(--border);
            color: var(--text-2);
            font-family: var(--font-mono);
            font-size: 10px;
            font-weight: 500;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            padding: 4px 10px;
            border-radius: 3px;
            cursor: pointer;
            transition: all 0.15s;
        }

        .btn-micro:hover {
            border-color: var(--border-2);
            color: var(--text);
        }

        .artist-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
            gap: 4px;
            max-height: 220px;
            overflow-y: auto;
            padding: 2px;
        }

        .artist-grid::-webkit-scrollbar { width: 4px; }
        .artist-grid::-webkit-scrollbar-track { background: transparent; }
        .artist-grid::-webkit-scrollbar-thumb { background: var(--border-2); border-radius: 2px; }

        .artist-row {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 6px 8px;
            border-radius: 3px;
            transition: background 0.1s;
        }

        .artist-row:hover { background: var(--surface-2); }

        .artist-row input[type="checkbox"] {
            accent-color: var(--accent);
            width: 13px;
            height: 13px;
            cursor: pointer;
            flex-shrink: 0;
        }

        .artist-row label {
            font-size: 13px;
            color: var(--text-2);
            cursor: pointer;
            flex: 1;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .artist-tc {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            flex-shrink: 0;
        }

        /* Player body */
        .player-body {
            padding: 28px;
        }

        .track-row {
            display: flex;
            gap: 24px;
            margin-bottom: 28px;
            align-items: flex-start;
        }

        .cover-wrap {
            width: 112px;
            height: 112px;
            flex-shrink: 0;
            border-radius: 4px;
            overflow: hidden;
            background: var(--surface-2);
            border: 1px solid var(--border);
        }

        .cover-wrap img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            display: block;
        }

        .track-meta {
            flex: 1;
            min-width: 0;
            padding-top: 6px;
        }

        .track-title-el {
            font-size: 20px;
            font-weight: 600;
            line-height: 1.2;
            margin-bottom: 6px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .track-artist-el {
            font-size: 14px;
            color: var(--text-2);
            margin-bottom: 16px;
        }

        .status-pill {
            display: inline-flex;
            align-items: center;
            gap: 5px;
            font-family: var(--font-mono);
            font-size: 10px;
            font-weight: 600;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            padding: 3px 8px;
            border-radius: 2px;
            background: var(--green-dim);
            color: var(--green);
        }

        .status-dot {
            width: 5px;
            height: 5px;
            border-radius: 50%;
            background: var(--green);
        }

        .status-pill.paused {
            background: var(--surface-2);
            color: var(--text-3);
        }

        .status-pill.paused .status-dot {
            background: var(--text-3);
        }

        /* Progress */
        .progress-wrap {
            margin-bottom: 6px;
            cursor: pointer;
        }

        .progress-track {
            height: 3px;
            background: var(--progress-bg);
            border-radius: 2px;
            position: relative;
            transition: height 0.15s;
        }

        .progress-wrap:hover .progress-track { height: 5px; }

        .progress-fill {
            height: 100%;
            background: var(--accent);
            border-radius: 2px;
            width: 0;
            transition: width 0.1s linear;
        }

        .time-row {
            display: flex;
            justify-content: space-between;
            font-family: var(--font-mono);
            font-size: 11px;
            color: var(--text-3);
            margin-bottom: 20px;
        }

        /* Controls */
        .controls-row {
            display: flex;
            align-items: center;
            gap: 8px;
            flex-wrap: wrap;
        }

        .btn-play {
            background: var(--accent);
            border: none;
            color: #fff;
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 600;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            padding: 9px 20px;
            border-radius: 4px;
            cursor: pointer;
            transition: background 0.15s, transform 0.1s;
            min-width: 80px;
        }

        .btn-play:hover { background: #2563eb; }
        .btn-play:active { transform: scale(0.97); }

        .btn-ctrl {
            background: var(--surface-2);
            border: 1px solid var(--border);
            color: var(--text-2);
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            padding: 8px 14px;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.15s;
        }

        .btn-ctrl:hover {
            border-color: var(--border-2);
            color: var(--text);
        }

        .volume-wrap {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-left: auto;
        }

        .volume-label {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }

        input[type="range"].vol {
            -webkit-appearance: none;
            width: 80px;
            height: 3px;
            background: var(--progress-bg);
            border-radius: 2px;
            outline: none;
            cursor: pointer;
        }

        input[type="range"].vol::-webkit-slider-thumb {
            -webkit-appearance: none;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: var(--accent);
            cursor: pointer;
        }

        /* Loading / error */
        .state-msg {
            padding: 40px 28px;
            font-family: var(--font-mono);
            font-size: 12px;
            color: var(--text-3);
            letter-spacing: 0.05em;
        }

        .error-banner {
            background: rgba(239,68,68,0.06);
            border: 1px solid rgba(239,68,68,0.2);
            color: #f87171;
            padding: 14px 20px;
            margin: 16px;
            border-radius: 4px;
            font-size: 13px;
            display: none;
        }

        /* Footer link */
        .player-link {
            display: block;
            text-align: center;
            padding: 14px;
            border-top: 1px solid var(--border);
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: var(--text-3);
            text-decoration: none;
            transition: color 0.15s, background 0.15s;
        }

        .player-link:hover {
            color: var(--accent);
            background: var(--accent-glow);
        }

        #audio-el { display: none; }

        @media (max-width: 520px) {
            .track-row { flex-direction: column; }
            .cover-wrap { width: 100%; height: 180px; }
            .volume-wrap { margin-left: 0; }
        }
    </style>
</head>
<body>

<div class="shell">
    <div class="header">
        <div class="wordmark">Jri <span>Radio</span></div>
        <div class="header-right">
            <button class="btn-ghost" id="theme-btn">Light</button>
        </div>
    </div>

    <div class="card" id="main-card">
        <div id="filter-panel" class="filter-panel">
            <div class="filter-header">
                <span class="filter-label">Artist Filter</span>
                <span class="filter-count" id="filter-count"></span>
            </div>
            <div class="filter-actions">
                <button class="btn-micro" id="sel-all">All</button>
                <button class="btn-micro" id="sel-none">None</button>
            </div>
            <div class="artist-grid" id="artist-grid"></div>
        </div>

        <div id="loading-msg" class="state-msg">Loading library...</div>
        <div id="error-msg" class="error-banner"></div>

        <div id="player-ui" style="display:none">
            <div class="player-body">
                <div class="track-row">
                    <div class="cover-wrap">
                        <img id="cover-img" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" alt="Cover">
                    </div>
                    <div class="track-meta">
                        <div class="track-title-el" id="track-title">--</div>
                        <div class="track-artist-el" id="track-artist">--</div>
                        <div class="status-pill paused" id="status-pill">
                            <span class="status-dot"></span>
                            <span id="status-text">Paused</span>
                        </div>
                    </div>
                </div>

                <div class="progress-wrap" id="progress-wrap">
                    <div class="progress-track">
                        <div class="progress-fill" id="progress-fill"></div>
                    </div>
                </div>
                <div class="time-row">
                    <span id="cur-time">0:00</span>
                    <span id="dur-time">0:00</span>
                </div>

                <div class="controls-row">
                    <button class="btn-play" id="play-btn">Play</button>
                    <button class="btn-ctrl" id="next-btn">Next</button>
                    <button class="btn-ctrl" id="filter-btn">Filter</button>
                    <div class="volume-wrap">
                        <span class="volume-label">Vol</span>
                        <input type="range" class="vol" id="vol-slider" min="0" max="1" step="0.05" value="1">
                    </div>
                </div>
            </div>
        </div>
    </div>

    <a href="player.html" class="player-link">Open full player &rarr;</a>
</div>

<audio id="audio-el"></audio>

<script>
(function () {
    'use strict';

    // -------------------------------------------------------------------
    // Tab title scroller
    // -------------------------------------------------------------------
    const TabScroller = (() => {
        let _timer = null;
        let _pos = 0;
        let _text = '';
        const SCROLL_INTERVAL = 220;
        const PADDING = '     ';  // space between loop

        function _tick() {
            document.title = _text.slice(_pos) + _text.slice(0, _pos);
            _pos = (_pos + 1) % _text.length;
        }

        return {
            start(title, artist) {
                TabScroller.stop();
                const full = `${title} - ${artist}`;
                _text = full + PADDING;
                _pos = 0;
                _tick();
                _timer = setInterval(_tick, SCROLL_INTERVAL);
            },
            pause(title, artist) {
                TabScroller.stop();
                document.title = `[Paused] ${title} - ${artist}`;
            },
            stop() {
                if (_timer) { clearInterval(_timer); _timer = null; }
            },
            idle() {
                TabScroller.stop();
                document.title = 'Jri Radio';
            }
        };
    })();

    // -------------------------------------------------------------------
    // Parse track data -- delimiter ||| avoids base64 = collision
    // -------------------------------------------------------------------
    function parseTrackData(raw) {
        const tracks = [];
        for (const line of raw.trim().split('\n')) {
            if (!line.startsWith('(') || !line.endsWith(')')) continue;
            const content = line.slice(1, -1);
            const idx1 = content.indexOf('|||');
            if (idx1 === -1) continue;
            const idx2 = content.indexOf('|||', idx1 + 3);
            if (idx2 === -1) continue;
            const idx3 = content.indexOf('|||', idx2 + 3);
            if (idx3 === -1) continue;

            const filename = content.slice(0, idx1);
            const title    = content.slice(idx1 + 3, idx2).replace(/_EQUAL_/g, '=');
            const artist   = content.slice(idx2 + 3, idx3).replace(/_EQUAL_/g, '=');
            const imgRaw   = content.slice(idx3 + 3);
            const image    = (imgRaw && imgRaw !== 'none') ? imgRaw : null;

            tracks.push({ filename, title, artist, image });
        }
        return tracks;
    }

    // -------------------------------------------------------------------
    // Raw URL builder
    // -------------------------------------------------------------------
    function rawUrl(filename) {
        return `https://raw.githubusercontent.com/Jri-creator/jri_site/refs/heads/main/${filename}`;
    }

    // -------------------------------------------------------------------
    // Player
    // -------------------------------------------------------------------
    class RadioPlayer {
        constructor() {
            this.audio        = document.getElementById('audio-el');
            this.playBtn      = document.getElementById('play-btn');
            this.nextBtn      = document.getElementById('next-btn');
            this.filterBtn    = document.getElementById('filter-btn');
            this.filterPanel  = document.getElementById('filter-panel');
            this.artistGrid   = document.getElementById('artist-grid');
            this.selAll       = document.getElementById('sel-all');
            this.selNone      = document.getElementById('sel-none');
            this.filterCount  = document.getElementById('filter-count');
            this.coverImg     = document.getElementById('cover-img');
            this.titleEl      = document.getElementById('track-title');
            this.artistEl     = document.getElementById('track-artist');
            this.statusPill   = document.getElementById('status-pill');
            this.statusText   = document.getElementById('status-text');
            this.progressWrap = document.getElementById('progress-wrap');
            this.progressFill = document.getElementById('progress-fill');
            this.curTime      = document.getElementById('cur-time');
            this.durTime      = document.getElementById('dur-time');
            this.volSlider    = document.getElementById('vol-slider');
            this.themeBtn     = document.getElementById('theme-btn');
            this.loadingMsg   = document.getElementById('loading-msg');
            this.errorMsg     = document.getElementById('error-msg');
            this.playerUI     = document.getElementById('player-ui');

            this.tracks          = [];
            this.allArtists      = new Map();
            this.enabledArtists  = new Set();
            this.queue           = [];
            this.queueIndex      = 0;
            this.isPlaying       = false;
            this.interacted      = false;
            this.filterOpen      = false;
            this.currentTrack    = null;

            document.addEventListener('click', () => { this.interacted = true; }, { once: true });
            document.addEventListener('keydown', () => { this.interacted = true; }, { once: true });

            this._bindEvents();
            this._init();
        }

        _bindEvents() {
            this.playBtn.addEventListener('click', () => this.togglePlay());
            this.nextBtn.addEventListener('click', () => this.next());
            this.filterBtn.addEventListener('click', () => this.toggleFilter());
            this.selAll.addEventListener('click', () => this.selectAll());
            this.selNone.addEventListener('click', () => this.selectNone());
            this.volSlider.addEventListener('input', e => this._setVolume(e.target.value));
            this.themeBtn.addEventListener('click', () => this.toggleTheme());

            this.audio.addEventListener('timeupdate', () => this._onTimeUpdate());
            this.audio.addEventListener('loadedmetadata', () => this._onMeta());
            this.audio.addEventListener('ended', () => this.next());
            this.audio.addEventListener('error', () => setTimeout(() => this.next(), 1200));
            this.audio.addEventListener('play', () => this._setPlayState(true));
            this.audio.addEventListener('pause', () => this._setPlayState(false));

            this.progressWrap.addEventListener('click', e => this._seek(e));
        }

        async _init() {
            this._applyStoredTheme();
            this._applyStoredVolume();

            try {
                const [countRes, dataRes] = await Promise.all([
                    fetch('./filecount.txt'),
                    fetch('./filedata.txt')
                ]);
                if (!countRes.ok || !dataRes.ok) throw new Error('fetch failed');
                const count = parseInt(await countRes.text(), 10);
                if (count === 0) { this._showError('No music files found.'); return; }
                const raw = await dataRes.text();
                this.tracks = parseTrackData(raw);
                if (this.tracks.length === 0) { this._showError('No valid tracks parsed.'); return; }
            } catch (e) {
                this._showError('Could not load music library.');
                return;
            }

            this._buildArtistMap();
            this._loadArtistPrefs();   // Must come after allArtists is built
            this._buildArtistUI();
            this._buildQueue();
            this._showPlayer();
            this._loadTrack(this.queue[0]);
        }

        _buildArtistMap() {
            this.allArtists.clear();
            for (const t of this.tracks) {
                this.allArtists.set(t.artist, (this.allArtists.get(t.artist) || 0) + 1);
            }
            this.allArtists = new Map([...this.allArtists].sort((a, b) => a[0].localeCompare(b[0])));
        }

        _loadArtistPrefs() {
            const saved = localStorage.getItem('jr_enabled_artists');
            if (saved) {
                try {
                    const arr = JSON.parse(saved);
                    // Only restore artists that still exist in the library
                    this.enabledArtists = new Set(arr.filter(a => this.allArtists.has(a)));
                } catch (_) {}
            }
            // Default or empty: enable all
            if (this.enabledArtists.size === 0) {
                this.enabledArtists = new Set(this.allArtists.keys());
            }
        }

        _saveArtistPrefs() {
            localStorage.setItem('jr_enabled_artists', JSON.stringify([...this.enabledArtists]));
        }

        _buildArtistUI() {
            this.artistGrid.innerHTML = '';
            for (const [artist, count] of this.allArtists) {
                const id = 'ar_' + artist.replace(/\W/g, '_');
                const row = document.createElement('div');
                row.className = 'artist-row';

                const cb = document.createElement('input');
                cb.type = 'checkbox';
                cb.id = id;
                cb.checked = this.enabledArtists.has(artist);
                cb.addEventListener('change', () => this._toggleArtist(artist, cb.checked, cb));

                const lbl = document.createElement('label');
                lbl.htmlFor = id;
                lbl.textContent = artist;
                lbl.title = artist;

                const tc = document.createElement('span');
                tc.className = 'artist-tc';
                tc.textContent = count;

                row.append(cb, lbl, tc);
                this.artistGrid.appendChild(row);
            }
            this._updateFilterCount();
        }

        _toggleArtist(artist, enabled, cb) {
            if (enabled) {
                this.enabledArtists.add(artist);
            } else {
                // Never disable the last artist
                if (this.enabledArtists.size <= 1) {
                    cb.checked = true;
                    return;
                }
                this.enabledArtists.delete(artist);
            }
            this._saveArtistPrefs();
            this._updateFilterCount();
            this._buildQueue();
        }

        selectAll() {
            this.enabledArtists = new Set(this.allArtists.keys());
            this._syncCheckboxes();
            this._saveArtistPrefs();
            this._updateFilterCount();
            this._buildQueue();
        }

        selectNone() {
            // Preserve the currently playing artist so playback isn't broken
            const keep = this.currentTrack ? this.currentTrack.artist
                : this.allArtists.keys().next().value;
            this.enabledArtists = new Set([keep]);
            this._syncCheckboxes();
            this._saveArtistPrefs();
            this._updateFilterCount();
            this._buildQueue();
        }

        _syncCheckboxes() {
            for (const [artist] of this.allArtists) {
                const id = 'ar_' + artist.replace(/\W/g, '_');
                const cb = document.getElementById(id);
                if (cb) cb.checked = this.enabledArtists.has(artist);
            }
        }

        _updateFilterCount() {
            const en = this.enabledArtists.size;
            const tot = this.allArtists.size;
            this.filterCount.textContent = en === tot ? 'All' : `${en} / ${tot}`;
        }

        _buildQueue() {
            const eligible = this.tracks.filter(t => this.enabledArtists.has(t.artist));
            // Fisher-Yates shuffle
            for (let i = eligible.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [eligible[i], eligible[j]] = [eligible[j], eligible[i]];
            }
            this.queue = eligible;
            this.queueIndex = 0;
        }

        _loadTrack(track) {
            if (!track) return;
            this.currentTrack = track;
            this.titleEl.textContent  = track.title;
            this.artistEl.textContent = track.artist;
            this.coverImg.src = track.image ||
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
            this.audio.src = rawUrl(track.filename);
            this.audio.load();
            TabScroller.pause(track.title, track.artist);
        }

        next() {
            this.queueIndex++;
            if (this.queueIndex >= this.queue.length) {
                this._buildQueue();
            }
            const track = this.queue[this.queueIndex];
            this._loadTrack(track);
            if (this.isPlaying && this.interacted) {
                this.audio.play().catch(() => {});
            }
        }

        togglePlay() {
            if (!this.interacted) this.interacted = true;
            if (this.audio.paused) {
                this.audio.play().catch(e => {
                    console.warn('Play blocked:', e);
                });
            } else {
                this.audio.pause();
            }
        }

        _setPlayState(playing) {
            this.isPlaying = playing;
            this.playBtn.textContent = playing ? 'Pause' : 'Play';
            this.statusPill.classList.toggle('paused', !playing);
            this.statusText.textContent = playing ? 'Live' : 'Paused';
            if (this.currentTrack) {
                if (playing) {
                    TabScroller.start(this.currentTrack.title, this.currentTrack.artist);
                } else {
                    TabScroller.pause(this.currentTrack.title, this.currentTrack.artist);
                }
            }
        }

        toggleFilter() {
            this.filterOpen = !this.filterOpen;
            this.filterPanel.classList.toggle('open', this.filterOpen);
            this.filterBtn.textContent = this.filterOpen ? 'Hide' : 'Filter';
            localStorage.setItem('jr_filter_open', this.filterOpen);
        }

        _setVolume(v) {
            this.audio.volume = v;
            localStorage.setItem('jr_volume', v);
        }

        _applyStoredVolume() {
            const v = localStorage.getItem('jr_volume');
            if (v !== null) {
                this.volSlider.value = v;
                this.audio.volume = parseFloat(v);
            }
        }

        _onTimeUpdate() {
            if (!this.audio.duration) return;
            const pct = (this.audio.currentTime / this.audio.duration) * 100;
            this.progressFill.style.width = pct + '%';
            this.curTime.textContent = _fmt(this.audio.currentTime);
        }

        _onMeta() {
            this.durTime.textContent = _fmt(this.audio.duration);
        }

        _seek(e) {
            if (!this.audio.duration) return;
            const rect = this.progressWrap.getBoundingClientRect();
            this.audio.currentTime = ((e.clientX - rect.left) / rect.width) * this.audio.duration;
        }

        toggleTheme() {
            const light = document.body.classList.toggle('light');
            this.themeBtn.textContent = light ? 'Dark' : 'Light';
            localStorage.setItem('jr_theme', light ? 'light' : 'dark');
        }

        _applyStoredTheme() {
            const t = localStorage.getItem('jr_theme');
            if (t === 'light') {
                document.body.classList.add('light');
                this.themeBtn.textContent = 'Dark';
            }
        }

        _showPlayer() {
            this.loadingMsg.style.display = 'none';
            this.playerUI.style.display = 'block';
            // Restore filter panel state
            if (localStorage.getItem('jr_filter_open') === 'true') {
                this.toggleFilter();
            }
        }

        _showError(msg) {
            this.loadingMsg.style.display = 'none';
            this.errorMsg.textContent = msg;
            this.errorMsg.style.display = 'block';
            TabScroller.idle();
        }
    }

    function _fmt(s) {
        if (!s || isNaN(s)) return '0:00';
        s = Math.floor(s);
        return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
    }

    document.addEventListener('DOMContentLoaded', () => new RadioPlayer());
})();
</script>
</body>
</html>
EOF

    echo "Created index.html"
}

# ---------------------------------------------------------------------------
# player.html -- Full music player
# ---------------------------------------------------------------------------
create_player_html() {
    echo "Creating player.html..."

    cat > "$PLAYER_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jri Player</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg:          #0a0a0c;
            --surface:     #111116;
            --surface-2:   #18181f;
            --border:      #222230;
            --border-2:    #2e2e40;
            --text:        #e8e8f0;
            --text-2:      #8888a0;
            --text-3:      #55556a;
            --accent:      #3b82f6;
            --accent-dim:  #1e3a5f;
            --accent-glow: rgba(59,130,246,0.12);
            --green:       #22c55e;
            --green-dim:   #14532d;
            --progress-bg: #1a1a24;
            --font-mono:   'IBM Plex Mono', monospace;
            --font-sans:   'IBM Plex Sans', sans-serif;
        }

        body.light {
            --bg:          #f4f4f8;
            --surface:     #ffffff;
            --surface-2:   #f0f0f5;
            --border:      #dddde8;
            --border-2:    #cbcbd8;
            --text:        #111118;
            --text-2:      #5a5a70;
            --text-3:      #9090a8;
            --accent:      #2563eb;
            --accent-dim:  #dbeafe;
            --accent-glow: rgba(37,99,235,0.08);
            --green:       #16a34a;
            --green-dim:   #dcfce7;
            --progress-bg: #e8e8f0;
        }

        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: var(--font-sans);
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            transition: background 0.2s, color 0.2s;
        }

        .shell {
            max-width: 1100px;
            margin: 0 auto;
            padding: 32px 24px;
        }

        /* Header */
        .header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 32px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border);
        }

        .wordmark {
            font-family: var(--font-mono);
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.12em;
            text-transform: uppercase;
            color: var(--text-2);
        }

        .wordmark span { color: var(--accent); }

        .btn-ghost {
            background: none;
            border: 1px solid var(--border-2);
            color: var(--text-2);
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            transition: border-color 0.15s, color 0.15s, background 0.15s;
        }

        .btn-ghost:hover {
            border-color: var(--accent);
            color: var(--accent);
            background: var(--accent-glow);
        }

        /* Layout */
        .layout {
            display: grid;
            grid-template-columns: 300px 1fr;
            gap: 16px;
            align-items: start;
        }

        @media (max-width: 720px) {
            .layout { grid-template-columns: 1fr; }
        }

        /* Panel */
        .panel {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 6px;
            overflow: hidden;
        }

        .panel-head {
            padding: 14px 18px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: var(--surface-2);
        }

        .panel-head-label {
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 600;
            letter-spacing: 0.1em;
            text-transform: uppercase;
            color: var(--text-3);
        }

        .track-count-badge {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            background: var(--surface);
            border: 1px solid var(--border);
            padding: 2px 7px;
            border-radius: 2px;
        }

        /* Search */
        .search-wrap {
            padding: 10px 14px;
            border-bottom: 1px solid var(--border);
        }

        .search-wrap input {
            width: 100%;
            background: var(--surface-2);
            border: 1px solid var(--border);
            color: var(--text);
            font-family: var(--font-sans);
            font-size: 13px;
            padding: 7px 11px;
            border-radius: 4px;
            outline: none;
            transition: border-color 0.15s;
        }

        .search-wrap input:focus { border-color: var(--accent); }
        .search-wrap input::placeholder { color: var(--text-3); }

        /* Library list */
        .lib-list {
            max-height: 520px;
            overflow-y: auto;
            padding: 6px;
            scrollbar-width: thin;
            scrollbar-color: var(--border-2) transparent;
        }

        .lib-list::-webkit-scrollbar { width: 4px; }
        .lib-list::-webkit-scrollbar-track { background: transparent; }
        .lib-list::-webkit-scrollbar-thumb { background: var(--border-2); border-radius: 2px; }

        .lib-item {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 9px 10px;
            border-radius: 4px;
            cursor: pointer;
            transition: background 0.1s;
            border: 1px solid transparent;
        }

        .lib-item:hover { background: var(--surface-2); }

        .lib-item.active {
            background: var(--accent-dim);
            border-color: rgba(59,130,246,0.2);
        }

        .lib-item.active .lib-title { color: var(--accent); }

        .lib-num {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            min-width: 22px;
            text-align: right;
        }

        .lib-info { flex: 1; min-width: 0; }

        .lib-title {
            font-size: 13px;
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            margin-bottom: 2px;
        }

        .lib-artist {
            font-size: 11px;
            color: var(--text-3);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        /* Now playing panel */
        .now-playing {
            padding: 32px 28px;
        }

        .art-wrap {
            width: 220px;
            height: 220px;
            margin: 0 auto 28px;
            border-radius: 4px;
            overflow: hidden;
            background: var(--surface-2);
            border: 1px solid var(--border);
        }

        .art-wrap img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            display: block;
        }

        .np-title {
            font-size: 22px;
            font-weight: 600;
            text-align: center;
            margin-bottom: 6px;
            line-height: 1.2;
        }

        .np-artist {
            font-size: 15px;
            color: var(--text-2);
            text-align: center;
            margin-bottom: 24px;
        }

        /* Progress */
        .prog-wrap {
            cursor: pointer;
            margin-bottom: 6px;
        }

        .prog-track {
            height: 3px;
            background: var(--progress-bg);
            border-radius: 2px;
            transition: height 0.15s;
        }

        .prog-wrap:hover .prog-track { height: 5px; }

        .prog-fill {
            height: 100%;
            background: var(--accent);
            border-radius: 2px;
            width: 0;
            transition: width 0.1s linear;
        }

        .time-row {
            display: flex;
            justify-content: space-between;
            font-family: var(--font-mono);
            font-size: 11px;
            color: var(--text-3);
            margin-bottom: 22px;
        }

        /* Controls */
        .ctrl-row {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            margin-bottom: 16px;
        }

        .btn-icon {
            background: var(--surface-2);
            border: 1px solid var(--border);
            color: var(--text-2);
            width: 40px;
            height: 40px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: all 0.15s;
            flex-shrink: 0;
        }

        .btn-icon:hover {
            border-color: var(--border-2);
            color: var(--text);
        }

        .btn-icon.active {
            background: var(--accent-dim);
            border-color: var(--accent);
            color: var(--accent);
        }

        .btn-icon svg { pointer-events: none; }

        .btn-play-lg {
            width: 52px;
            height: 52px;
            background: var(--accent);
            border: none;
            color: #fff;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: background 0.15s, transform 0.1s;
            flex-shrink: 0;
        }

        .btn-play-lg:hover { background: #2563eb; }
        .btn-play-lg:active { transform: scale(0.94); }

        .mode-label {
            font-family: var(--font-mono);
            font-size: 9px;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: var(--text-3);
            text-align: center;
            margin-top: 3px;
        }

        .btn-icon.active .mode-label { color: var(--accent); }

        .vol-row {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            margin-bottom: 20px;
        }

        .vol-label {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }

        input[type="range"].vol {
            -webkit-appearance: none;
            width: 100px;
            height: 3px;
            background: var(--progress-bg);
            border-radius: 2px;
            outline: none;
            cursor: pointer;
        }

        input[type="range"].vol::-webkit-slider-thumb {
            -webkit-appearance: none;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: var(--accent);
            cursor: pointer;
        }

        /* Keyboard hint */
        .kb-hint {
            font-family: var(--font-mono);
            font-size: 10px;
            color: var(--text-3);
            text-align: center;
            line-height: 1.8;
            letter-spacing: 0.03em;
        }

        /* Back link */
        .back-link {
            display: inline-block;
            margin-top: 18px;
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: var(--text-3);
            text-decoration: none;
            transition: color 0.15s;
        }

        .back-link:hover { color: var(--accent); }

        .state-msg {
            padding: 40px;
            font-family: var(--font-mono);
            font-size: 12px;
            color: var(--text-3);
        }
    </style>
</head>
<body>

<div class="shell">
    <div class="header">
        <div class="wordmark">Jri <span>Player</span></div>
        <button class="btn-ghost" id="theme-btn">Light</button>
    </div>

    <div class="layout">
        <!-- Library -->
        <div class="panel">
            <div class="panel-head">
                <span class="panel-head-label">Library</span>
                <span class="track-count-badge" id="track-badge">0</span>
            </div>
            <div class="search-wrap">
                <input type="text" id="search" placeholder="Search tracks, artists...">
            </div>
            <div class="lib-list" id="lib-list">
                <div class="state-msg">Loading...</div>
            </div>
        </div>

        <!-- Player -->
        <div class="panel">
            <div class="now-playing">
                <div class="art-wrap">
                    <img id="cover-img" src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxIDEiLz4=" alt="Cover">
                </div>
                <div class="np-title" id="np-title">No track selected</div>
                <div class="np-artist" id="np-artist">Select a track to begin</div>

                <div class="prog-wrap" id="prog-wrap">
                    <div class="prog-track">
                        <div class="prog-fill" id="prog-fill"></div>
                    </div>
                </div>
                <div class="time-row">
                    <span id="cur-time">0:00</span>
                    <span id="dur-time">0:00</span>
                </div>

                <div class="ctrl-row">
                    <div>
                        <button class="btn-icon" id="shuf-btn" title="Shuffle">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                                <polyline points="16,3 21,3 21,8"></polyline>
                                <line x1="4" y1="20" x2="21" y2="3"></line>
                                <polyline points="21,16 21,21 16,21"></polyline>
                                <line x1="15" y1="15" x2="21" y2="21"></line>
                                <line x1="4" y1="4" x2="9" y2="9"></line>
                            </svg>
                        </button>
                        <div class="mode-label" id="shuf-label">Off</div>
                    </div>

                    <button class="btn-icon" id="prev-btn" title="Previous">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                            <polygon points="19 20 9 12 19 4 19 20"></polygon>
                            <line x1="5" y1="19" x2="5" y2="5"></line>
                        </svg>
                    </button>

                    <button class="btn-play-lg" id="play-btn" title="Play/Pause">
                        <svg id="play-icon" width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                            <polygon points="5 3 19 12 5 21 5 3"></polygon>
                        </svg>
                        <svg id="pause-icon" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" style="display:none">
                            <rect x="6" y="4" width="4" height="16"></rect>
                            <rect x="14" y="4" width="4" height="16"></rect>
                        </svg>
                    </button>

                    <button class="btn-icon" id="next-btn" title="Next">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                            <polygon points="5 4 15 12 5 20 5 4"></polygon>
                            <line x1="19" y1="5" x2="19" y2="19"></line>
                        </svg>
                    </button>

                    <div>
                        <button class="btn-icon" id="rep-btn" title="Repeat">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                                <polyline points="17,1 21,5 17,9"></polyline>
                                <path d="m21 5h-9a4 4 0 0 0-4 4v6"></path>
                                <polyline points="7,23 3,19 7,15"></polyline>
                                <path d="m3 19h9a4 4 0 0 0 4-4v-6"></path>
                            </svg>
                        </button>
                        <div class="mode-label" id="rep-label">Off</div>
                    </div>
                </div>

                <div class="vol-row">
                    <span class="vol-label">Vol</span>
                    <input type="range" class="vol" id="vol-slider" min="0" max="1" step="0.05" value="1">
                </div>

                <div class="kb-hint">
                    Space &nbsp;Play/Pause &nbsp;&bull;&nbsp; &larr;&rarr; &nbsp;Seek &nbsp;&bull;&nbsp; P &nbsp;Prev &nbsp;&bull;&nbsp; N &nbsp;Next &nbsp;&bull;&nbsp; S &nbsp;Shuffle &nbsp;&bull;&nbsp; R &nbsp;Repeat
                </div>

                <a href="index.html" class="back-link">&larr; Back to Radio</a>
            </div>
        </div>
    </div>
</div>

<audio id="audio-el"></audio>

<script>
(function () {
    'use strict';

    // -------------------------------------------------------------------
    // Tab title scroller
    // -------------------------------------------------------------------
    const TabScroller = (() => {
        let _timer = null;
        let _pos = 0;
        let _text = '';
        const INTERVAL = 220;
        const PAD = '     ';

        function _tick() {
            document.title = _text.slice(_pos) + _text.slice(0, _pos);
            _pos = (_pos + 1) % _text.length;
        }

        return {
            start(title, artist) {
                TabScroller.stop();
                const full = `${title} - ${artist}`;
                _text = full + PAD;
                _pos = 0;
                _tick();
                _timer = setInterval(_tick, INTERVAL);
            },
            pause(title, artist) {
                TabScroller.stop();
                document.title = `[Paused] ${title} - ${artist}`;
            },
            stop() {
                if (_timer) { clearInterval(_timer); _timer = null; }
            },
            idle() {
                TabScroller.stop();
                document.title = 'Jri Player';
            }
        };
    })();

    // -------------------------------------------------------------------
    // Parse track data -- ||| delimiter avoids base64 = collision
    // -------------------------------------------------------------------
    function parseTrackData(raw) {
        const tracks = [];
        for (const line of raw.trim().split('\n')) {
            if (!line.startsWith('(') || !line.endsWith(')')) continue;
            const content = line.slice(1, -1);
            const i1 = content.indexOf('|||');
            if (i1 === -1) continue;
            const i2 = content.indexOf('|||', i1 + 3);
            if (i2 === -1) continue;
            const i3 = content.indexOf('|||', i2 + 3);
            if (i3 === -1) continue;

            tracks.push({
                filename: content.slice(0, i1),
                title:    content.slice(i1 + 3, i2).replace(/_EQUAL_/g, '='),
                artist:   content.slice(i2 + 3, i3).replace(/_EQUAL_/g, '='),
                image:    (() => { const v = content.slice(i3 + 3); return (v && v !== 'none') ? v : null; })()
            });
        }
        return tracks;
    }

    function rawUrl(filename) {
        return `https://raw.githubusercontent.com/Jri-creator/jri_site/refs/heads/main/${filename}`;
    }

    function fmt(s) {
        if (!s || isNaN(s)) return '0:00';
        s = Math.floor(s);
        return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
    }

    // -------------------------------------------------------------------
    // Player
    // -------------------------------------------------------------------
    class MusicPlayer {
        constructor() {
            this.audio      = document.getElementById('audio-el');
            this.playBtn    = document.getElementById('play-btn');
            this.playIcon   = document.getElementById('play-icon');
            this.pauseIcon  = document.getElementById('pause-icon');
            this.prevBtn    = document.getElementById('prev-btn');
            this.nextBtn    = document.getElementById('next-btn');
            this.shufBtn    = document.getElementById('shuf-btn');
            this.shufLabel  = document.getElementById('shuf-label');
            this.repBtn     = document.getElementById('rep-btn');
            this.repLabel   = document.getElementById('rep-label');
            this.coverImg   = document.getElementById('cover-img');
            this.npTitle    = document.getElementById('np-title');
            this.npArtist   = document.getElementById('np-artist');
            this.progWrap   = document.getElementById('prog-wrap');
            this.progFill   = document.getElementById('prog-fill');
            this.curTime    = document.getElementById('cur-time');
            this.durTime    = document.getElementById('dur-time');
            this.volSlider  = document.getElementById('vol-slider');
            this.themeBtn   = document.getElementById('theme-btn');
            this.libList    = document.getElementById('lib-list');
            this.search     = document.getElementById('search');
            this.trackBadge = document.getElementById('track-badge');

            this.tracks       = [];
            this.filtered     = [];
            this.currentIdx   = -1;
            this.isPlaying    = false;
            this.interacted   = false;
            this.shuffled     = false;
            this.repeatMode   = 'off';    // 'off' | 'one'
            this.shuffleOrder = [];
            this.shufflePos   = -1;

            document.addEventListener('click', () => { this.interacted = true; }, { once: true });
            this._bind();
            this._init();
        }

        _bind() {
            this.playBtn.addEventListener('click',  () => this.togglePlay());
            this.prevBtn.addEventListener('click',  () => this.prev());
            this.nextBtn.addEventListener('click',  () => this.next());
            this.shufBtn.addEventListener('click',  () => this.toggleShuffle());
            this.repBtn.addEventListener('click',   () => this.toggleRepeat());
            this.volSlider.addEventListener('input', e => this._setVol(e.target.value));
            this.themeBtn.addEventListener('click', () => this.toggleTheme());
            this.search.addEventListener('input',   () => this._filter());
            this.progWrap.addEventListener('click', e => this._seek(e));

            this.audio.addEventListener('timeupdate',    () => this._onTime());
            this.audio.addEventListener('loadedmetadata',() => this._onMeta());
            this.audio.addEventListener('ended',         () => this._onEnd());
            this.audio.addEventListener('error',         () => setTimeout(() => this.next(), 1200));
            this.audio.addEventListener('play',          () => this._setPlayUI(true));
            this.audio.addEventListener('pause',         () => this._setPlayUI(false));

            document.addEventListener('keydown', e => this._keys(e));
        }

        async _init() {
            this._applyStoredTheme();
            this._applyStoredVol();
            this._loadModes();

            try {
                const [cr, dr] = await Promise.all([
                    fetch('./filecount.txt'),
                    fetch('./filedata.txt')
                ]);
                if (!cr.ok || !dr.ok) throw new Error('fetch failed');
                const count = parseInt(await cr.text(), 10);
                if (count === 0) { this._err('No music files found.'); return; }
                this.tracks = parseTrackData(await dr.text());
                if (this.tracks.length === 0) { this._err('No valid tracks parsed.'); return; }
            } catch (e) {
                this._err('Could not load music library.');
                return;
            }

            this.filtered = [...this.tracks];
            this.trackBadge.textContent = this.tracks.length;
            this._renderLib();
            this._genShuffleOrder();
            TabScroller.idle();
        }

        _renderLib() {
            if (this.filtered.length === 0) {
                this.libList.innerHTML = '<div class="state-msg">No results.</div>';
                return;
            }

            this.libList.innerHTML = this.filtered.map(track => {
                const realIdx = this.tracks.indexOf(track);
                const active  = realIdx === this.currentIdx ? ' active' : '';
                return `<div class="lib-item${active}" data-idx="${realIdx}">
                    <span class="lib-num">${realIdx + 1}</span>
                    <div class="lib-info">
                        <div class="lib-title">${_esc(track.title)}</div>
                        <div class="lib-artist">${_esc(track.artist)}</div>
                    </div>
                </div>`;
            }).join('');

            this.libList.querySelectorAll('.lib-item').forEach(el => {
                el.addEventListener('click', () => this.play(parseInt(el.dataset.idx, 10)));
            });
        }

        _filter() {
            const q = this.search.value.toLowerCase().trim();
            this.filtered = q
                ? this.tracks.filter(t =>
                    t.title.toLowerCase().includes(q) ||
                    t.artist.toLowerCase().includes(q))
                : [...this.tracks];
            this._renderLib();
        }

        play(idx) {
            if (idx < 0 || idx >= this.tracks.length) return;
            this.currentIdx = idx;
            const t = this.tracks[idx];

            this.npTitle.textContent  = t.title;
            this.npArtist.textContent = t.artist;
            this.coverImg.src = t.image || _blank();

            this.audio.src = rawUrl(t.filename);
            this.audio.load();

            if (this.isPlaying) this.audio.play().catch(() => {});
            else if (this.interacted) {
                this.audio.play().catch(() => {});
            }

            // Update shuffle position
            if (this.shuffled) {
                this.shufflePos = this.shuffleOrder.indexOf(idx);
            }

            this._renderLib(); // Re-render to update active state
            TabScroller.pause(t.title, t.artist);

            if ('mediaSession' in navigator) {
                navigator.mediaSession.metadata = new MediaMetadata({
                    title: t.title, artist: t.artist,
                    artwork: [{ src: t.image || _blank(), sizes: '512x512', type: 'image/jpeg' }]
                });
            }
        }

        togglePlay() {
            this.interacted = true;
            if (this.currentIdx === -1 && this.tracks.length > 0) { this.play(0); return; }
            if (this.audio.paused) this.audio.play().catch(() => {});
            else this.audio.pause();
        }

        _setPlayUI(playing) {
            this.isPlaying = playing;
            this.playIcon.style.display  = playing ? 'none' : 'block';
            this.pauseIcon.style.display = playing ? 'block' : 'none';
            const t = this.tracks[this.currentIdx];
            if (t) {
                if (playing) TabScroller.start(t.title, t.artist);
                else         TabScroller.pause(t.title, t.artist);
            }
            if ('mediaSession' in navigator) {
                navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
            }
        }

        next() {
            const idx = this._nextIdx();
            if (idx !== -1) this.play(idx);
        }

        prev() {
            // If more than 3s in, restart; otherwise go back
            if (this.audio.currentTime > 3) {
                this.audio.currentTime = 0;
                return;
            }
            const idx = this._prevIdx();
            if (idx !== -1) this.play(idx);
        }

        _nextIdx() {
            if (this.tracks.length === 0) return -1;
            if (this.shuffled) {
                this.shufflePos = (this.shufflePos + 1) % this.shuffleOrder.length;
                return this.shuffleOrder[this.shufflePos];
            }
            return (this.currentIdx + 1) % this.tracks.length;
        }

        _prevIdx() {
            if (this.tracks.length === 0) return -1;
            if (this.shuffled) {
                this.shufflePos = (this.shufflePos - 1 + this.shuffleOrder.length) % this.shuffleOrder.length;
                return this.shuffleOrder[this.shufflePos];
            }
            return (this.currentIdx - 1 + this.tracks.length) % this.tracks.length;
        }

        _onEnd() {
            if (this.repeatMode === 'one') {
                this.audio.currentTime = 0;
                this.audio.play().catch(() => {});
            } else {
                this.next();
            }
        }

        toggleShuffle() {
            this.shuffled = !this.shuffled;
            if (this.shuffled) {
                this._genShuffleOrder();
                this.shufflePos = this.shuffleOrder.indexOf(this.currentIdx);
            }
            this.shufBtn.classList.toggle('active', this.shuffled);
            this.shufLabel.textContent = this.shuffled ? 'On' : 'Off';
            localStorage.setItem('jp_shuffle', this.shuffled);
        }

        toggleRepeat() {
            this.repeatMode = this.repeatMode === 'off' ? 'one' : 'off';
            const on = this.repeatMode !== 'off';
            this.repBtn.classList.toggle('active', on);
            this.repLabel.textContent = on ? '1' : 'Off';
            localStorage.setItem('jp_repeat', this.repeatMode);
        }

        _genShuffleOrder() {
            this.shuffleOrder = Array.from({ length: this.tracks.length }, (_, i) => i);
            for (let i = this.shuffleOrder.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [this.shuffleOrder[i], this.shuffleOrder[j]] = [this.shuffleOrder[j], this.shuffleOrder[i]];
            }
        }

        _loadModes() {
            this.shuffled = localStorage.getItem('jp_shuffle') === 'true';
            this.repeatMode = localStorage.getItem('jp_repeat') || 'off';
            this.shufBtn.classList.toggle('active', this.shuffled);
            this.shufLabel.textContent = this.shuffled ? 'On' : 'Off';
            const repOn = this.repeatMode !== 'off';
            this.repBtn.classList.toggle('active', repOn);
            this.repLabel.textContent = repOn ? '1' : 'Off';
        }

        _setVol(v) {
            this.audio.volume = v;
            localStorage.setItem('jp_volume', v);
        }

        _applyStoredVol() {
            const v = localStorage.getItem('jp_volume');
            if (v !== null) { this.volSlider.value = v; this.audio.volume = parseFloat(v); }
        }

        _onTime() {
            if (!this.audio.duration) return;
            this.progFill.style.width = (this.audio.currentTime / this.audio.duration * 100) + '%';
            this.curTime.textContent = fmt(this.audio.currentTime);
        }

        _onMeta() {
            this.durTime.textContent = fmt(this.audio.duration);
        }

        _seek(e) {
            if (!this.audio.duration) return;
            const r = this.progWrap.getBoundingClientRect();
            this.audio.currentTime = ((e.clientX - r.left) / r.width) * this.audio.duration;
        }

        toggleTheme() {
            const light = document.body.classList.toggle('light');
            this.themeBtn.textContent = light ? 'Dark' : 'Light';
            localStorage.setItem('jp_theme', light ? 'light' : 'dark');
        }

        _applyStoredTheme() {
            if (localStorage.getItem('jp_theme') === 'light') {
                document.body.classList.add('light');
                this.themeBtn.textContent = 'Dark';
            }
        }

        _keys(e) {
            if (e.target.tagName === 'INPUT') return;
            switch (e.code) {
                case 'Space':      e.preventDefault(); this.togglePlay(); break;
                case 'ArrowLeft':  e.preventDefault(); this.audio.currentTime = Math.max(0, this.audio.currentTime - 5); break;
                case 'ArrowRight': e.preventDefault(); this.audio.currentTime = Math.min(this.audio.duration || 0, this.audio.currentTime + 5); break;
                case 'KeyN':       e.preventDefault(); this.next(); break;
                case 'KeyP':       e.preventDefault(); this.prev(); break;
                case 'KeyS':       e.preventDefault(); this.toggleShuffle(); break;
                case 'KeyR':       e.preventDefault(); this.toggleRepeat(); break;
            }
        }

        _err(msg) {
            this.libList.innerHTML = `<div class="state-msg">${_esc(msg)}</div>`;
            TabScroller.idle();
        }
    }

    function _esc(s) {
        return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    function _blank() {
        return 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxIDEiLz4=';
    }

    document.addEventListener('DOMContentLoaded', () => {
        new MusicPlayer();

        if ('mediaSession' in navigator) {
            const mp = window._mp = new MusicPlayer();
            // mediaSession handlers set inside play()
        }
    });
})();
</script>
</body>
</html>
EOF

    echo "Created player.html"
}

# ---------------------------------------------------------------------------
# Git commit & push
# ---------------------------------------------------------------------------
setup_github_pages() {
    echo "Setting up GitHub Pages..."

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not in a git repository. Please run this script inside your git repo."
        exit 1
    fi

    git add "$SITE_DIR/"

    if git diff --staged --quiet; then
        echo "No changes to commit"
    else
        git commit -m "Update Jri Radio site

- File count: $(cat $FILECOUNT_FILE)
- Date: $(cat $DATE_FILE)"
        echo "Committed"
    fi

    if git remote get-url origin > /dev/null 2>&1; then
        git push origin main 2>/dev/null || git push origin master 2>/dev/null || echo "Push failed -- push manually"
        echo "Pushed to remote"
    else
        echo "No remote 'origin' found. Add a remote and push manually."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "Jri Radio Publisher v2.0"
    echo "========================"

    check_dependencies
    count_files

    if [ "$(cat $FILECOUNT_FILE)" -gt 0 ]; then
        extract_metadata
        get_commit_date
        create_radio_html
        create_player_html
        setup_github_pages

        echo ""
        echo "Done."
        echo "Files processed : $(cat $FILECOUNT_FILE)"
        echo "Last update     : $(cat $DATE_FILE)"
        echo "Output dir      : $SITE_DIR/"
        echo ""
        echo "To enable GitHub Pages: Settings > Pages > Deploy from branch > main (or master), /site folder"
        echo "Note: .jlres3 files are served via GitHub raw content URLs"
    else
        echo "No .jlres3 files found."
        exit 1
    fi
}

main "$@"
