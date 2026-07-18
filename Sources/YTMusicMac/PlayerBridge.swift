import Foundation

enum PlayerBridge {

    // ---------- CSS features (toggleable from native) ----------
    /// "Native Mode" — hides YT Music's entire visible UI by collapsing
    /// the app-layout. The <video> element underneath keeps playing audio,
    /// so the WebView is now just an invisible audio engine. Our SwiftUI
    /// shell covers what the user actually sees.
    static let hideYTAppCSS = #"""
    ytmusic-app-layout,
    ytmusic-nav-bar,
    ytmusic-player-bar,
    ytmusic-popup-container,
    tp-yt-app-drawer {
      display: none !important;
    }
    /* Belt-and-suspenders: even if a single element slips through, the
       body background goes dark so there's no white frame around the
       SwiftUI overlay. */
    html, body, ytmusic-app {
      background: #030303 !important;
    }
    """#
    /// Bootstrap script: installs each feature as a separate `<style id="__ytm_<name>">`
    /// element. `window.__ytmSetFeature(name, on)` flips `style.disabled` to enable
    /// or disable a feature live without reloading the page.
    /// "Clip mode" — pin the <video> element full-window on top of everything
    /// so the music video plays edge-to-edge. Used together with disabling
    /// hideYTApp (the video lives inside the app-layout we normally collapse).
    static let videoOnlyCSS = #"""
    video {
      position: fixed !important;
      inset: 0 !important;
      width: 100vw !important;
      height: 100vh !important;
      object-fit: contain !important;
      z-index: 2147483000 !important;
      background: #000 !important;
    }
    html, body, ytmusic-app { background: #000 !important; }
    """#

    static var cssBootstrapScript: String {
        let features: [(name: String, css: String, default: Bool)] = [
            ("hideYTApp", hideYTAppCSS, false),
            ("videoOnly", videoOnlyCSS, false)
        ]
        let entries = features.map { f -> String in
            // JS-escape the CSS string (backticks + backslashes + ${ })
            let escaped = f.css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")
            let defaultOn = f.default ? "false" : "true"  // style.disabled is INVERSE of enabled
            return "  { name: '\(f.name)', css: `\(escaped)`, startDisabled: \(defaultOn) }"
        }.joined(separator: ",\n")

        return """
        (function() {
          if (window.__ytmCSSInjected) return;
          window.__ytmCSSInjected = true;

          var FEATURES = [
        \(entries)
          ];

          function installAll() {
            FEATURES.forEach(function(f) {
              if (document.getElementById('__ytm_' + f.name)) return;
              var s = document.createElement('style');
              s.id = '__ytm_' + f.name;
              s.textContent = f.css;
              s.disabled = f.startDisabled;
              (document.head || document.documentElement).appendChild(s);
            });
          }

          if (document.head) installAll();
          else document.addEventListener('DOMContentLoaded', installAll);

          window.__ytmSetFeature = function(name, enabled) {
            var s = document.getElementById('__ytm_' + name);
            if (s) s.disabled = !enabled;
          };

          // Live theme swap: rewrites a single style element's contents.
          window.__ytmSetTheme = function(css) {
            var s = document.getElementById('__ytm_theme__');
            if (!s) {
              s = document.createElement('style');
              s.id = '__ytm_theme__';
              (document.head || document.documentElement).appendChild(s);
            }
            s.textContent = css || '';
          };
        })();
        """
    }

    // ---------- Console log capture ----------

    static let consoleCaptureScript = #"""
    (function() {
      if (window.__ytmLogInjected) return;
      window.__ytmLogInjected = true;
      function fwd(level, args) {
        try {
          var text = Array.prototype.map.call(args, function(a) {
            if (a instanceof Error) return a.message + ' @ ' + (a.stack || '');
            if (typeof a === 'object') { try { return JSON.stringify(a); } catch(e) { return String(a); } }
            return String(a);
          }).join(' ');
          window.webkit.messageHandlers.ytmLog.postMessage({ level: level, text: text });
        } catch(e) {}
      }
      ['error', 'warn'].forEach(function(level) {
        var orig = console[level];
        console[level] = function() { fwd(level, arguments); orig.apply(console, arguments); };
      });
      window.addEventListener('error', function(e) {
        fwd('uncaught', [e.message + ' @ ' + e.filename + ':' + e.lineno]);
      });
      window.addEventListener('unhandledrejection', function(e) {
        fwd('promise', [(e.reason && e.reason.message) || String(e.reason)]);
      });
    })();
    """#

    // ---------- Player bridge: state + commands ----------

    static let injectionScript = #"""
    (function() {
      if (window.__ytmInjected) return;
      window.__ytmInjected = true;

      function q(sel) { return document.querySelector(sel); }

      // ---------- Autoplay suppression (after idle reload) ----------
      // The idle reloader sets localStorage '__ytmSuppressAutoplay' to an
      // expiry timestamp BEFORE reloading. Until it expires, pause any video
      // that tries to play — so a 30-min-paused session doesn't spontaneously
      // resume the current /watch track in the background after the reload.
      (function() {
        var until = 0;
        try { until = parseInt(localStorage.getItem('__ytmSuppressAutoplay') || '0', 10) || 0; } catch (e) {}
        if (Date.now() >= until) {
          try { localStorage.removeItem('__ytmSuppressAutoplay'); } catch (e) {}
          return;
        }
        var guard = setInterval(function() {
          try {
            if (Date.now() >= until) {
              clearInterval(guard);
              try { localStorage.removeItem('__ytmSuppressAutoplay'); } catch (e) {}
              return;
            }
            var v = q('video');
            if (v && !v.paused) v.pause();
          } catch (e) {}
        }, 150);
      })();

      // Shuffle/repeat state lives on the <ytmusic-player-bar> element, not
      // on the buttons (which expose no aria-pressed). shuffle-on is a boolean
      // attribute; repeat-mode is "NONE" | "ALL" | "ONE".
      function shuffleIsOn() {
        try { var b = q('ytmusic-player-bar'); return !!(b && b.hasAttribute('shuffle-on')); }
        catch (e) { return false; }
      }
      function repeatModeStr() {
        try { var b = q('ytmusic-player-bar'); return (b && b.getAttribute('repeat-mode')) || 'NONE'; }
        catch (e) { return 'NONE'; }
      }

      // The player bar's like renderer, not whichever one happens to come
      // first in the document (list rows carry their own).
      function likeRenderer() {
        return q('ytmusic-player-bar ytmusic-like-button-renderer')
            || q('ytmusic-like-button-renderer');
      }

      function likeStatus() {
        try {
          var el = likeRenderer();
          return el ? el.getAttribute('like-status') : null;
        } catch (e) { return null; }
      }

      // `#button-shape-like` is a <yt-button-shape>, and the click handler
      // lives on the <button> it wraps — clicking the wrapper does nothing.
      function likeButton(kind) {
        try {
          var r = likeRenderer();
          if (!r) return null;
          var shape = r.querySelector('#button-shape-' + kind);
          if (shape) return shape.querySelector('button') || shape;
          var sel = kind === 'dislike'
            ? 'button[aria-label*="dislike" i], button[aria-label*="beğenme" i]'
            : 'button[aria-label*="like" i]:not([aria-label*="dislike" i]), button[aria-label*="beğen" i]:not([aria-label*="beğenme" i])';
          return r.querySelector(sel);
        } catch (e) { return null; }
      }

      // YT Music shows a Song/Video toggle only when a music video counterpart
      // exists for the current track. Its presence == "this track has a clip".
      function hasVideoToggle() {
        try { return !!q('ytmusic-av-toggle'); } catch (e) { return false; }
      }
      // Click the Video (or Song) segment of that toggle.
      function switchAV(toVideo) {
        try {
          var t = q('ytmusic-av-toggle');
          if (!t) return;
          var want = toVideo ? 'video' : 'song';
          var btns = t.querySelectorAll('button, tp-yt-paper-button, [role="button"], a');
          for (var i = 0; i < btns.length; i++) {
            var lbl = ((btns[i].getAttribute('aria-label') || '') + ' ' + (btns[i].textContent || '')).toLowerCase();
            if (lbl.indexOf(want) !== -1) { btns[i].click(); return; }
          }
          // Fallback: the toggle itself flips between the two states.
          (btns[toVideo ? btns.length - 1 : 0] || t).click();
        } catch (e) {}
      }

      // The URL is the usual source, but YT doesn't always carry ?v= (queue
      // advances on some pages leave it behind), and Native Mode's like
      // button needs a videoId to hit the API with. The player bar's own
      // like button knows exactly which video it would rate — ask it.
      function currentVideoId() {
        try {
          var m = location.href.match(/[?&]v=([^&]+)/);
          if (m) return decodeURIComponent(m[1]);
        } catch (e) {}
        try {
          var r = q('ytmusic-player-bar ytmusic-like-button-renderer')
               || q('ytmusic-like-button-renderer');
          var d = r && (r.data || r.data_);
          var vid = d && d.target && d.target.videoId;
          if (vid) return vid;
        } catch (e) {}
        return '';
      }
      function send() {
        try {
          var v = q('video');
          var titleEl = q('.title.ytmusic-player-bar') || q('.content-info-wrapper .title');
          var artistEl = q('.byline.ytmusic-player-bar') || q('.subtitle.ytmusic-player-bar');
          var artEl = q('.image.ytmusic-player-bar') || q('img.ytmusic-player-bar');
          var payload = {
            playing: v ? !v.paused : false,
            currentTime: v ? v.currentTime : 0,
            duration: (v && isFinite(v.duration)) ? v.duration : 0,
            // Report the user's INTENDED volume, not the momentary faded
            // value — otherwise the native slider would dance during a fade.
            volume: (window.__ytmBaseVolume != null ? window.__ytmBaseVolume : (v ? v.volume : 1)),
            title: titleEl ? titleEl.textContent.trim() : '',
            artist: artistEl ? artistEl.textContent.trim() : '',
            artwork: artEl ? artEl.src : '',
            videoId: currentVideoId(),
            liked: likeStatus() === 'LIKE',
            disliked: likeStatus() === 'DISLIKE',
            shuffle: shuffleIsOn(),
            repeatMode: repeatModeStr(),
            hasVideo: hasVideoToggle()
          };
          window.webkit.messageHandlers.ytmBridge.postMessage(payload);
        } catch (e) {}
      }
      // Event-driven: react instantly to playback state changes instead of
      // polling 670x/min. MPNowPlayingInfoCenter interpolates currentTime
      // between updates using playbackRate, so we don't need timeupdate.
      var __ytmSendPending = false;
      function sendSoon() {
        if (__ytmSendPending) return;
        __ytmSendPending = true;
        setTimeout(function() { __ytmSendPending = false; send(); }, 50);
      }
      function attachVideoListeners() {
        var v = q('video');
        if (!v || v.__ytmListened) return !!v;
        v.__ytmListened = true;
        // NOTE: 'volumechange' is intentionally NOT in this list. The
        // crossfade ramp writes v.volume ~8x/sec; routing those through
        // sendSoon would flood the native bridge. User volume changes come
        // through __ytmCmd('volume'), which calls sendSoon() itself.
        ['play', 'pause', 'seeked', 'ratechange',
         'loadedmetadata', 'durationchange', 'ended'].forEach(function(ev) {
          v.addEventListener(ev, sendSoon);
        });
        // Crossfade drivers: run the volume ramp only while actually playing.
        v.addEventListener('play', startFadeTicker);
        v.addEventListener('pause', stopFadeTicker);
        v.addEventListener('ended', stopFadeTicker);
        v.addEventListener('loadedmetadata', applyFade);
        // Distinct 'ended' notification for own-queue chaining — separate
        // from the player-state poll so native can react in one hop.
        // Filter spurious 'ended' events: YT clears video.src during
        // its own track changes which fires 'ended' at currentTime=0,
        // and that was making our ownQueue jump in unexpectedly.
        v.addEventListener('ended', function() {
          try {
            if (!v.duration || !isFinite(v.duration)) return;
            if (v.currentTime < v.duration - 1.5) return;
            window.webkit.messageHandlers.ytmEvent.postMessage({ name: 'ended' });
          } catch (e) {}
        });
        // Shuffle keeper: re-enable shuffle every time a new track starts
        // unless the user explicitly disabled it recently (see ensureShuffle).
        v.addEventListener('loadedmetadata', function() {
          setTimeout(function() { ensureShuffle('loadedmetadata'); }, 400);
        });
        sendSoon();
        return true;
      }

      // ---------- Shuffle keeper ----------
      // YT Music resets shuffle to OFF every time a new queue starts (e.g.
      // user clicks a specific track in a playlist). This keeps it pinned ON
      // by re-clicking the shuffle button on each track change, with a 30s
      // grace window so manual "turn shuffle off" still works.
      window.__ytmAlwaysShuffle = (typeof window.__ytmAlwaysShuffle === 'boolean')
        ? window.__ytmAlwaysShuffle : true;
      window.__ytmUserToggledShuffleAt = 0;

      window.__ytmSetAlwaysShuffle = function(on) {
        window.__ytmAlwaysShuffle = !!on;
        if (on) setTimeout(function() { ensureShuffle('setAlwaysShuffle'); }, 200);
      };

      // A radio queue (RDAMVM…) must start on the track the user seeded it
      // with, but YT resets shuffle when the queue opens and the keeper would
      // switch it back on — which reshuffles the queue and skips the seed.
      // Armed by native right before/after the radio navigation; released
      // once the seed hands over to the next track.
      // A radio (RDAMVM…) queue is already an endless shuffled mix, and
      // toggling shuffle mid-queue makes YT re-draw it — which skips whatever
      // is playing. So the keeper stays out of radio pages entirely. Native
      // sets this on the page the radio navigation lands on; it dies with the
      // document, so any other navigation clears it for free.
      window.__ytmRadioPage = window.__ytmRadioPage || false;
      window.__ytmArmShuffleGuard = function() { window.__ytmRadioPage = true; };

      function findShuffleBtn() {
        return q('ytmusic-player-bar tp-yt-paper-icon-button.shuffle')
            || q('ytmusic-player-bar yt-button-shape[aria-label*="shuffle" i] button')
            || q('ytmusic-player-bar [aria-label*="shuffle" i]')
            || q('ytmusic-player-bar [aria-label*="karıştır" i]')
            || q('ytmusic-player-bar [aria-label*="rastgele" i]');
      }
      function isShufflePressed(btn) {
        if (!btn) return false;
        if (btn.getAttribute('aria-pressed') === 'true') return true;
        if (btn.getAttribute('aria-checked') === 'true') return true;
        if (btn.classList && (btn.classList.contains('selected')
                           || btn.classList.contains('active'))) return true;
        if (btn.hasAttribute('active')) return true;
        // Some versions style the active state on a parent button-shape
        var shape = btn.closest('yt-button-shape');
        if (shape && shape.getAttribute('aria-pressed') === 'true') return true;
        return false;
      }
      function attachShuffleClickListener() {
        var btn = findShuffleBtn();
        if (!btn || btn.__ytmShuffleListened) return;
        btn.__ytmShuffleListened = true;
        // Capture phase so we record the click before YT's own handler
        // toggles aria-pressed.
        btn.addEventListener('click', function() {
          // Our own ensureShuffle click lands here too; counting it would
          // arm the manual-toggle grace window against ourselves.
          if (window.__ytmSelfClickingShuffle) return;
          window.__ytmUserToggledShuffleAt = Date.now();
        }, true);
      }
      // Why does this retry? A click on YT's shuffle button silently no-ops
      // while the player is still booting — the button is in the DOM long
      // before it does anything. Clicking once and trusting it left shuffle
      // off for ~10s after opening a track, so the first Next played in order.
      // Verify against shuffle-on and keep trying until it actually sticks.
      // Turning shuffle on makes YT re-draw the queue, which skips whatever is
      // playing. YT only resets shuffle when a NEW queue opens, and in this app
      // a new queue means a new document — so settle it once per page load and
      // then stay out of the way. Fighting every later reset costs a skipped
      // track each time.
      window.__ytmShuffleSettled = window.__ytmShuffleSettled || false;
      var __ytmShuffleRun = 0;
      function ensureShuffle(why, deadline) {
        var run = ++__ytmShuffleRun;   // newest call wins; no duelling loops
        var until = deadline || (Date.now() + 20000);
        (function attempt() {
          try {
            if (run !== __ytmShuffleRun) return;
            if (window.__ytmShuffleSettled) return;
            if (!window.__ytmAlwaysShuffle) return;
            if (window.__ytmRadioPage) return;
            // Respect a manual toggle for 30s so user can listen sequentially.
            if (Date.now() - window.__ytmUserToggledShuffleAt < 30000) return;
            attachShuffleClickListener();
            // A click no-ops while YT's player is still booting, so verify
            // against shuffle-on and retry until it actually takes.
            if (shuffleIsOn()) { window.__ytmShuffleSettled = true; return; }
            var btn = findShuffleBtn();
            if (btn) {
              window.__ytmSelfClickingShuffle = true;
              try { btn.click(); } finally {
                setTimeout(function() { window.__ytmSelfClickingShuffle = false; }, 0);
              }
            }
            if (Date.now() < until) setTimeout(attempt, 400);
          } catch (e) {}
        })();
      }
      // One-shot attach attempt right after the bridge installs.
      setTimeout(attachShuffleClickListener, 1500);
      // Try to attach until the <video> element appears (YT mounts it after
      // user interaction). Stops polling once attached.
      var __ytmAttachTimer = setInterval(function() {
        if (attachVideoListeners()) clearInterval(__ytmAttachTimer);
      }, 800);
      // Safety net for state that has no DOM event: title/artist/artwork
      // change on track switch (loadedmetadata catches most), like/dislike
      // clicks from inside YT's UI, etc. 4s is plenty for these.
      setInterval(send, 4000);

      // ---------- Crossfade / auto-fade ----------
      // True Spotify-style overlap isn't possible with YT's single <video>
      // element, so we do the perceptual equivalent: fade the tail of the
      // outgoing track down to silence over the last N seconds, then fade the
      // head of the incoming track up from silence over its first N seconds.
      // The whole ramp lives here in JS driven by a short ticker so it stays
      // smooth without waking the native side.
      window.__ytmFadeEnabled = (typeof window.__ytmFadeEnabled === 'boolean') ? window.__ytmFadeEnabled : false;
      window.__ytmFadeDur = (typeof window.__ytmFadeDur === 'number') ? window.__ytmFadeDur : 5;
      // The user's INTENDED volume (0..1). Every fade scales this; the native
      // slider reads this, never the momentary faded value. Persisted under
      // our own key so a mid-fade write YT may have stored can't corrupt it.
      window.__ytmBaseVolume = (typeof window.__ytmBaseVolume === 'number') ? window.__ytmBaseVolume : null;
      (function() {
        try {
          var sb = parseFloat(localStorage.getItem('__ytm_base_volume') || '');
          if (isFinite(sb)) window.__ytmBaseVolume = Math.max(0, Math.min(1, sb));
        } catch (e) {}
      })();

      function fadeSetVolume(v, val) {
        var clamped = Math.max(0, Math.min(1, val));
        if (Math.abs(v.volume - clamped) > 0.0005) v.volume = clamped;
      }
      function applyFade() {
        try {
          var v = q('video');
          if (!v) return;
          if (window.__ytmBaseVolume == null) window.__ytmBaseVolume = v.volume;
          var base = window.__ytmBaseVolume, dur = window.__ytmFadeDur;
          if (!window.__ytmFadeEnabled || dur <= 0) { fadeSetVolume(v, base); return; }
          var D = v.duration, t = v.currentTime;
          // Skip fading for tracks too short to hold both a fade-in and out.
          if (!isFinite(D) || D <= 0 || D < dur * 2 + 1) { fadeSetVolume(v, base); return; }
          var target = base;
          if (t < dur) target = base * (t / dur);                          // fade in
          else if (t > D - dur) target = base * Math.max(0, (D - t) / dur); // fade out
          fadeSetVolume(v, target);
        } catch (e) {}
      }
      var __ytmFadeTimer = null;
      function startFadeTicker() {
        if (__ytmFadeTimer || !window.__ytmFadeEnabled) return;
        __ytmFadeTimer = setInterval(function() {
          var v = q('video');
          if (!v || v.paused) { stopFadeTicker(); return; }
          applyFade();
        }, 120);
      }
      function stopFadeTicker() {
        if (__ytmFadeTimer) { clearInterval(__ytmFadeTimer); __ytmFadeTimer = null; }
      }
      window.__ytmSetFade = function(enabled, dur) {
        window.__ytmFadeEnabled = !!enabled;
        if (typeof dur === 'number') window.__ytmFadeDur = Math.max(0, Math.min(12, dur));
        var v = q('video');
        if (window.__ytmFadeEnabled && v && !v.paused) startFadeTicker();
        else { stopFadeTicker(); applyFade(); } // restore base volume if we were mid-fade
      };

      window.__ytmCmd = function(cmd, arg) {
        try {
          var v = q('video');
          if (cmd === 'playpause') { if (v) { v.paused ? v.play() : v.pause(); } return; }
          if (cmd === 'seek')      { if (v && typeof arg === 'number') v.currentTime = arg; return; }
          if (cmd === 'volume')    {
            if (typeof arg === 'number') {
              var nb = Math.max(0, Math.min(1, arg));
              window.__ytmBaseVolume = nb;
              try { localStorage.setItem('__ytm_base_volume', String(nb)); } catch (e) {}
              // Apply now; the ticker re-scales it if we're inside a fade zone.
              if (v) fadeSetVolume(v, nb);
              sendSoon();
            }
            return;
          }
          if (cmd === 'like' || cmd === 'dislike') {
            var lb = likeButton(cmd);
            if (lb) lb.click();
            setTimeout(send, 250); // re-read like-status after YT updates it
            return;
          }
          if (cmd === 'shuffle') {
            // Toggle YT's real shuffle button, then sync the always-shuffle
            // keeper to the new state so it maintains the user's choice (with
            // a 30s grace window so it doesn't immediately fight it).
            var wasOn = shuffleIsOn();
            var sb = findShuffleBtn();
            if (sb) sb.click();
            window.__ytmAlwaysShuffle = !wasOn;
            window.__ytmShuffleSettled = false;
            window.__ytmUserToggledShuffleAt = Date.now();
            setTimeout(send, 200); // re-read shuffle-on after YT updates it
            return;
          }
          if (cmd === 'shuffleon' || cmd === 'shuffleoff') {
            // Explicitly set shuffle state (used by the header Play/Shuffle
            // buttons so Play = in order, Shuffle = shuffled).
            var want = (cmd === 'shuffleon');
            window.__ytmAlwaysShuffle = want;
            window.__ytmShuffleSettled = false;
            window.__ytmUserToggledShuffleAt = want ? 0 : Date.now();
            var sbtn = findShuffleBtn();
            if (sbtn && shuffleIsOn() !== want) sbtn.click();
            if (want) setTimeout(function() { ensureShuffle('cmd:shuffleon'); }, 300);
            setTimeout(send, 250);
            return;
          }
          if (cmd === 'repeat') {
            // Cycle YT's repeat button (NONE -> ALL -> ONE -> NONE).
            var rb = q('.repeat.ytmusic-player-bar')
                  || q('ytmusic-player-bar tp-yt-paper-icon-button.repeat')
                  || q('ytmusic-player-bar [aria-label*="repeat" i]')
                  || q('ytmusic-player-bar [aria-label*="yinele" i]')
                  || q('ytmusic-player-bar [aria-label*="tekrar" i]');
            if (rb) { var ib = rb.querySelector('button') || rb; ib.click(); }
            setTimeout(send, 200); // re-read repeat-mode after YT updates it
            return;
          }
          if (cmd === 'togglePlayer') {
            // YT Music's existing expand-to-player-page button (▲ in the
            // bottom-right of the player bar). Selectors cover several
            // YT Music versions + TR/EN labels.
            var btn = q('ytmusic-player-bar .player-minimize-button')
                   || q('ytmusic-player-bar tp-yt-paper-icon-button.expand-button')
                   || q('.expand-button.ytmusic-player-bar')
                   || q('ytmusic-player-bar [aria-label*="büyüt" i]')
                   || q('ytmusic-player-bar [aria-label*="expand" i]')
                   || q('ytmusic-player-bar [aria-label*="genişlet" i]')
                   || q('ytmusic-player-bar [aria-label*="minimize" i]')
                   || q('ytmusic-player-bar [aria-label*="küçült" i]');
            if (btn) btn.click();
            return;
          }
          var map = {
            next: '.next-button.ytmusic-player-bar',
            prev: '.previous-button.ytmusic-player-bar'
          };
          var sel = map[cmd];
          if (!sel) return;
          var btn = q(sel);
          if (btn) btn.click();
        } catch (e) {}
      };

      // ---------- Clip (music video) mode ----------
      // Switches YT to the video counterpart and injects an always-visible
      // "back" button so the user can exit even if native layering hiccups.
      // YT Music's <video> lives inside a shadow DOM, so an injected document
      // <style> can't reach it. Setting the element's INLINE style does (it
      // applies directly to the node), so we pin it full-window that way.
      function pinVideo() {
        var v = q('video');
        if (!v) return;
        // YT's player container has a `transform`, which traps position:fixed
        // inside it instead of the viewport. Moving the <video> to be a direct
        // child of <body> escapes that containing block. The element keeps
        // playing across the move. We stash its original parent to restore later.
        if (v.parentElement !== document.body) {
          if (!v.__ytmOrigParent) v.__ytmOrigParent = v.parentElement;
          document.body.appendChild(v);
        }
        // YT's own transport bar is behind us now, so give the <video> its
        // native HTML5 controls (play/pause + seek bar + volume).
        v.controls = true;
        var s = v.style;
        s.setProperty('position', 'fixed', 'important');
        s.setProperty('top', '0', 'important');
        s.setProperty('left', '0', 'important');
        s.setProperty('width', '100vw', 'important');
        s.setProperty('height', '100vh', 'important');
        s.setProperty('max-width', 'none', 'important');
        s.setProperty('max-height', 'none', 'important');
        s.setProperty('object-fit', 'contain', 'important');
        // Just below the injected back button (2147483646) so it stays clickable.
        s.setProperty('z-index', '2147483000', 'important');
        s.setProperty('background', '#000', 'important');
      }
      function unpinVideo() {
        var v = q('video');
        if (!v) return;
        ['position','top','left','width','height','max-width','max-height',
         'object-fit','z-index','background'].forEach(function(p) {
          v.style.removeProperty(p);
        });
        v.controls = false; // hand transport back to YT
        // Put the video back where YT expects it.
        if (v.__ytmOrigParent) {
          try { v.__ytmOrigParent.appendChild(v); } catch (e) {}
          v.__ytmOrigParent = null;
        }
      }

      var __ytmClipProbe = null;
      window.__ytmEnterClip = function() {
        try {
          switchAV(true);
          pinVideo();
          if (!document.getElementById('__ytm_clip_back')) {
            var b = document.createElement('button');
            b.id = '__ytm_clip_back';
            b.textContent = '‹ Kapağa dön';
            b.style.cssText = 'position:fixed;top:16px;left:16px;z-index:2147483646;'
              + 'padding:8px 14px;border-radius:999px;border:none;cursor:pointer;'
              + 'background:rgba(0,0,0,0.6);color:#fff;font:600 13px -apple-system,sans-serif;'
              + 'backdrop-filter:blur(8px);';
            b.onclick = function() {
              try { window.webkit.messageHandlers.ytmEvent.postMessage({ name: 'exitClip' }); } catch (e) {}
            };
            document.body.appendChild(b);
          }
          // Title + artist to the right of the back button, so it's clear
          // whose clip this is.
          if (!document.getElementById('__ytm_clip_meta')) {
            var titleEl = q('.title.ytmusic-player-bar') || q('.content-info-wrapper .title');
            var artistEl = q('.byline.ytmusic-player-bar') || q('.subtitle.ytmusic-player-bar');
            var m = document.createElement('div');
            m.id = '__ytm_clip_meta';
            m.style.cssText = 'position:fixed;top:14px;left:150px;z-index:2147483646;'
              + 'color:#fff;font-family:-apple-system,sans-serif;pointer-events:none;'
              + 'text-shadow:0 1px 3px rgba(0,0,0,0.6);max-width:60vw;';
            var t = document.createElement('div');
            t.textContent = titleEl ? titleEl.textContent.trim() : '';
            t.style.cssText = 'font:600 14px -apple-system,sans-serif;white-space:nowrap;'
              + 'overflow:hidden;text-overflow:ellipsis;';
            var a = document.createElement('div');
            a.textContent = artistEl ? artistEl.textContent.trim() : '';
            a.style.cssText = 'font:400 12px -apple-system,sans-serif;opacity:0.75;'
              + 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
            m.appendChild(t); m.appendChild(a);
            document.body.appendChild(m);
          }
          // Confirm a REAL video is playing (audio-only tracks keep
          // videoHeight === 0). If nothing shows after ~5s, tell native so
          // it can bail out cleanly instead of leaving a black screen.
          if (__ytmClipProbe) clearInterval(__ytmClipProbe);
          // Per-track state. On next/prev, YT resets to the Song (audio)
          // version, so we must re-select video and re-evaluate each track.
          var tries = 0, sawVideo = false, bailed = false, curVid = currentVideoId();
          __ytmClipProbe = setInterval(function() {
            var nowVid = currentVideoId();
            if (nowVid && nowVid !== curVid) {
              // Track changed. Tell native whether this track has a video so it
              // can keep the video path (spinner) or drop to the crawl without
              // flashing lyrics. Re-select the video version if one exists.
              curVid = nowVid; tries = 0; sawVideo = false; bailed = false;
              var hv = hasVideoToggle();
              if (hv) switchAV(true);
              try { window.webkit.messageHandlers.ytmEvent.postMessage({ name: 'clipTrackChanged', hasVideo: hv }); } catch (e) {}
            }
            tries++;
            pinVideo(); // reparent + style, re-assert every tick
            // Keep the title/artist label in step with track changes.
            var mm = document.getElementById('__ytm_clip_meta');
            if (mm && mm.children.length >= 2) {
              var te = q('.title.ytmusic-player-bar') || q('.content-info-wrapper .title');
              var ae = q('.byline.ytmusic-player-bar') || q('.subtitle.ytmusic-player-bar');
              var nt = te ? te.textContent.trim() : '';
              var na = ae ? ae.textContent.trim() : '';
              if (mm.children[0].textContent !== nt) mm.children[0].textContent = nt;
              if (mm.children[1].textContent !== na) mm.children[1].textContent = na;
            }
            var v = q('video');
            if (v && v.videoHeight > 0) {
              if (!sawVideo) {
                sawVideo = true;
                // Real frame exists → native raises the WebView over the crawl.
                try { window.webkit.messageHandlers.ytmEvent.postMessage({ name: 'clipReady' }); } catch (e) {}
              }
            } else if (!sawVideo && !bailed && tries > 12) {
              // No real video for this track → stay on the crawl. Keep the probe
              // running so a later track WITH video can promote back.
              bailed = true;
              try { window.webkit.messageHandlers.ytmEvent.postMessage({ name: 'clipUnavailable' }); } catch (e) {}
            }
          }, 300);
        } catch (e) {}
      };
      window.__ytmExitClip = function() {
        try {
          if (__ytmClipProbe) { clearInterval(__ytmClipProbe); __ytmClipProbe = null; }
          unpinVideo();
          var b = document.getElementById('__ytm_clip_back');
          if (b) b.remove();
          var m = document.getElementById('__ytm_clip_meta');
          if (m) m.remove();
          switchAV(false); // back to the audio-only "Song" version
        } catch (e) {}
      };

      window.__ytmFocusSearch = function() {
        try {
          var input = q('ytmusic-search-box input') || q('input#input');
          if (input) { input.focus(); input.select && input.select(); }
        } catch (e) {}
      };

      // ---------- Queue read + jump ----------
      // Surfaces YT's player queue so the SwiftUI shell can render its
      // own queue panel. Read on yt-navigate-finish + on player-bar
      // mutations + on each track change (loadedmetadata).
      function readQueue() {
        try {
          var items = document.querySelectorAll('ytmusic-player-queue-item');
          var out = [];
          var playingIndex = -1;
          var lastKey = null;
          for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var titleEl = item.querySelector('.song-title, yt-formatted-string.song-title');
            var artistEl = item.querySelector('.byline, yt-formatted-string.byline');
            var imgEl = item.querySelector('yt-img-shadow img, img');
            var title = titleEl ? titleEl.textContent.trim() : '';
            var artist = artistEl ? artistEl.textContent.trim() : '';
            // YT ships a "counterpart" (e.g. video version) as a second
            // adjacent queue-item with the same title+artist. Collapse those
            // consecutive duplicates so each track shows once. We keep the
            // real DOM index `i` so __ytmJumpQueue still targets the right row.
            var key = title + '|' + artist;
            if (key === lastKey) continue;
            lastKey = key;
            var selected = item.hasAttribute('selected') ||
                           item.getAttribute('aria-selected') === 'true' ||
                           item.classList.contains('selected');
            if (selected) playingIndex = i;
            // videoId lives on the queue item's data property — needed for
            // context-menu actions (like, add-to-playlist, etc.).
            var videoId = '';
            try {
              var d = item.data || (item.data_ && item.data_.itemData) || null;
              if (d && d.videoId) videoId = d.videoId;
              if (!videoId && d && d.endpoint && d.endpoint.watchEndpoint) {
                videoId = d.endpoint.watchEndpoint.videoId || '';
              }
              if (!videoId) {
                // fallback: search any anchor for v= param
                var a = item.querySelector('a[href*="watch?v="]');
                if (a) {
                  var m = a.href.match(/v=([^&]+)/);
                  if (m) videoId = m[1];
                }
              }
            } catch (e) {}
            out.push({
              index: i,
              videoId: videoId,
              title: title,
              artist: artist,
              thumbnail: imgEl ? imgEl.src : '',
              isPlaying: selected
            });
          }
          window.webkit.messageHandlers.ytmQueue.postMessage({
            items: out, playingIndex: playingIndex, total: out.length
          });
        } catch (e) {}
      }

      var __ytmQueuePending = false;
      function scheduleQueueRead() {
        if (__ytmQueuePending) return;
        __ytmQueuePending = true;
        setTimeout(function() { __ytmQueuePending = false; readQueue(); }, 200);
      }

      // Jump to a specific queue index. The play target on YT's own queue
      // items is the song-title link — simulating a click on that starts
      // playback at that row inside the current queue.
      window.__ytmJumpQueue = function(index) {
        try {
          var items = document.querySelectorAll('ytmusic-player-queue-item');
          if (!items[index]) return;
          var target = items[index].querySelector('.song-title') ||
                       items[index].querySelector('a.yt-simple-endpoint') ||
                       items[index];
          ['mousedown', 'mouseup', 'click'].forEach(function(t) {
            target.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true }));
          });
        } catch (e) {}
      };

      // Hook into our existing track-change listener path: each time a new
      // track starts, the queue's `selected` row changes too.
      function attachQueueHooks() {
        var v = q('video');
        if (v && !v.__ytmQueueListened) {
          v.__ytmQueueListened = true;
          v.addEventListener('loadedmetadata', scheduleQueueRead);
          v.addEventListener('play', scheduleQueueRead);
        }
        var queue = q('ytmusic-player-queue');
        if (queue && !queue.__ytmObs) {
          queue.__ytmObs = true;
          new MutationObserver(scheduleQueueRead)
            .observe(queue, { childList: true, subtree: true });
        }
        return !!(v || queue);
      }
      var __ytmQueueHookTimer = setInterval(function() {
        if (attachQueueHooks()) clearInterval(__ytmQueueHookTimer);
      }, 1000);
      window.addEventListener('yt-navigate-finish', scheduleQueueRead);

      // Double-click a track row to play it. Default YT Music requires
      // clicking the hover-revealed play icon — annoying. We listen at the
      // document level so this works for any list (playlists, search,
      // library, album pages…).
      function ytmFindRow(target) {
        // Walk up looking for any of the known row-element tag names.
        var node = target;
        while (node && node !== document.body) {
          var t = (node.tagName || '').toLowerCase();
          if (t === 'ytmusic-responsive-list-item-renderer'
           || t === 'ytmusic-playlist-add-to-option-renderer'
           || t === 'ytmusic-shelf-renderer'  // fallback
          ) return node;
          node = node.parentElement || (node.getRootNode && node.getRootNode().host) || null;
        }
        return null;
      }
      function ytmFindPlayTarget(row) {
        // The track title anchor is YT Music's actual "play this row" hit
        // target — clicking it starts playback. Everything else (thumbnail,
        // play-button overlays) is inconsistent across views.
        return row.querySelector('.title-column a.yt-simple-endpoint')
            || row.querySelector('a.yt-simple-endpoint.ytmusic-responsive-list-item-renderer')
            || row.querySelector('a.yt-simple-endpoint');
      }
      function ytmFire(el) {
        // Polymer/Lit elements sometimes ignore .click() if they listen for
        // raw MouseEvents. Dispatch a synthetic one with bubbling.
        el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        el.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true }));
        el.dispatchEvent(new MouseEvent('click',     { bubbles: true, cancelable: true }));
      }
      document.addEventListener('dblclick', function(e) {
        try {
          var row = ytmFindRow(e.target);
          if (!row) return;
          if (e.target.closest('button, a, tp-yt-paper-icon-button, ytmusic-menu-renderer, [role="button"], input')) return;
          var target = ytmFindPlayTarget(row);
          if (target) {
            e.preventDefault();
            e.stopPropagation();
            ytmFire(target);
          }
        } catch (err) {}
      }, true);

      // ---------- Sidebar playlist cover thumbnails ----------
      // YT Music's left nav only shows playlist names, no thumbnails. We
      // lazy-cache each playlist's cover URL the first time the user opens
      // it (read from the detail header), then prepend a small <img> to
      // every matching sidebar link. Covers persist in localStorage.
      function playlistIdFromHref(href) {
        if (!href) return null;
        var m = href.match(/list=([A-Za-z0-9_-]+)/);
        return m ? m[1] : null;
      }
      function currentPlaylistId() {
        try {
          if (location.pathname === '/playlist') {
            return new URLSearchParams(location.search).get('list');
          }
        } catch (e) {}
        return null;
      }
      // Cache holds both byId and byTitle. byTitle is what the sidebar
      // decorator actually uses, because the sidebar entries use
      // `<tp-yt-paper-item>` instead of `<a>` and we can't reliably get
      // their playlist id from the DOM.
      function loadCache() {
        try {
          var c = JSON.parse(localStorage.getItem('__ytm_pl_covers__') || '{}');
          if (!c.byId)    c.byId = {};
          if (!c.byTitle) c.byTitle = {};
          return c;
        } catch (e) { return { byId: {}, byTitle: {} }; }
      }
      function saveCache(c) {
        try { localStorage.setItem('__ytm_pl_covers__', JSON.stringify(c)); } catch (e) {}
      }

      function smallerCover(url) {
        // YT image URLs accept a sizing suffix like "=w56-h56-l90-rj".
        // Strip any existing one and request a small thumbnail.
        return url.replace(/=[a-z0-9-]+$/, '') + '=w56-h56-l90-rj';
      }

      function plLog(msg) {
        try { window.webkit.messageHandlers.ytmLog.postMessage({ level: 'sidebar', text: msg }); } catch (e) {}
      }

      function extractCurrentCover() {
        var pid = currentPlaylistId();
        if (!pid) return;
        var imgCandidates = [
          document.querySelector('ytmusic-detail-header-renderer yt-img-shadow img'),
          document.querySelector('ytmusic-responsive-header-renderer yt-img-shadow img'),
          document.querySelector('ytmusic-detail-header-renderer img.image'),
          document.querySelector('ytmusic-responsive-header-renderer img.image'),
          document.querySelector('ytmusic-detail-header-renderer img'),
          document.querySelector('ytmusic-responsive-header-renderer img')
        ];
        var src = null;
        for (var i = 0; i < imgCandidates.length; i++) {
          if (imgCandidates[i] && imgCandidates[i].src && imgCandidates[i].src.startsWith('http')) {
            src = imgCandidates[i].src; break;
          }
        }
        if (!src) return;
        // Pick up the playlist title text from whichever header renderer is live
        var titleEl =
          document.querySelector('ytmusic-detail-header-renderer .title.ytmusic-detail-header-renderer') ||
          document.querySelector('ytmusic-responsive-header-renderer .title.ytmusic-responsive-header-renderer') ||
          document.querySelector('ytmusic-detail-header-renderer yt-formatted-string.title') ||
          document.querySelector('ytmusic-responsive-header-renderer yt-formatted-string.title') ||
          document.querySelector('ytmusic-detail-header-renderer h1, ytmusic-responsive-header-renderer h1');
        var title = titleEl ? titleEl.textContent.trim() : null;

        var cache = loadCache();
        var changed = false;
        if (cache.byId[pid] !== src) { cache.byId[pid] = src; changed = true; }
        if (title) {
          var key = title.toLowerCase();
          if (cache.byTitle[key] !== src) { cache.byTitle[key] = src; changed = true; }
        }
        if (changed) {
          saveCache(cache);
          plLog('cached pid=' + pid + ' title=' + (title || '?'));
          decorateSidebar();
        }
      }

      function decorateSidebar() {
        var cache = loadCache();
        var entries = document.querySelectorAll('ytmusic-guide-entry-renderer');
        if (entries.length === 0) return;

        var decorated = 0, withTitle = 0;
        entries.forEach(function(entry) {
          var titleEl = entry.querySelector('.title.ytmusic-guide-entry-renderer, .title-group yt-formatted-string, yt-formatted-string.title');
          var title = titleEl ? titleEl.textContent.trim().toLowerCase() : null;
          if (!title) return;
          withTitle++;
          var src = cache.byTitle[title];
          if (!src) return;
          // Insert thumb into .title-column (a plain div, safe to restyle).
          // Default .title-column is flex column (stacks title above subtitle);
          // override to flex row so the thumb sits LEFT of the title-group.
          var host = entry.querySelector('.title-column.ytmusic-guide-entry-renderer, .title-column');
          if (!host) return;
          host.style.setProperty('display', 'flex', 'important');
          host.style.setProperty('flex-direction', 'row', 'important');
          host.style.setProperty('align-items', 'center', 'important');
          host.style.setProperty('gap', '10px', 'important');
          var thumb = host.querySelector(':scope > .__ytm_pl_cover__');
          var smallSrc = smallerCover(src);
          if (thumb) {
            if (thumb.src !== smallSrc) thumb.src = smallSrc;
            return;
          }
          thumb = document.createElement('img');
          thumb.className = '__ytm_pl_cover__';
          thumb.src = smallSrc;
          thumb.referrerPolicy = 'no-referrer';
          thumb.style.cssText = 'width:28px;height:28px;border-radius:4px;flex-shrink:0;object-fit:cover;background:rgba(255,255,255,0.05);pointer-events:none;';
          host.prepend(thumb);
          decorated++;
        });
        plLog('decorate: entries=' + entries.length + ' withTitle=' + withTitle + ' decorated=' + decorated + ' cachedTitles=' + Object.keys(cache.byTitle).length);
      }

      // Scrape any playlist tile we can see on the page (home, library,
      // explore…) so the sidebar fills in WITHOUT the user having to open
      // each playlist individually.
      function scrapeVisibleTiles() {
        var cache = loadCache();
        var changed = false;
        var tiles = document.querySelectorAll('ytmusic-two-row-item-renderer, ytmusic-responsive-list-item-renderer');
        tiles.forEach(function(tile) {
          var imgEl = tile.querySelector('yt-img-shadow img, img.thumbnail');
          if (!imgEl || !imgEl.src || !imgEl.src.startsWith('http')) return;
          if (imgEl.src.indexOf('default') !== -1) return;
          var titleEl = tile.querySelector('a.yt-simple-endpoint yt-formatted-string.title, yt-formatted-string.title');
          if (!titleEl) return;
          var title = titleEl.textContent.trim().toLowerCase();
          if (!title) return;
          if (cache.byTitle[title] !== imgEl.src) {
            cache.byTitle[title] = imgEl.src;
            changed = true;
          }
          // If a link with list= is available, also cache by id
          var link = tile.querySelector('a[href*="list="]');
          if (link) {
            var pid = playlistIdFromHref(link.getAttribute('href'));
            if (pid && cache.byId[pid] !== imgEl.src) {
              cache.byId[pid] = imgEl.src;
              changed = true;
            }
          }
        });
        if (changed) {
          saveCache(cache);
          decorateSidebar();
        }
      }

      // Stacked layout disabled — earlier DOM mutation broke YT Music's
      // router. Keeping a stub so call sites compile.
      function tryFlattenPlaylistPage() { /* no-op */ }

      function tryExtract() {
        if (currentPlaylistId()) {
          [400, 1200, 2500].forEach(function(d) { setTimeout(extractCurrentCover, d); });
        }
        [600, 1500, 3000].forEach(function(d) { setTimeout(scrapeVisibleTiles, d); });
      }
      tryExtract();
      window.addEventListener('yt-navigate-finish', tryExtract);

      // Sidebar + tile work used to be 6000ms setInterval — querySelectorAll
      // over the whole DOM, every six seconds, forever. Now we observe the
      // two regions we actually care about (sidebar guide + main content
      // area) and only react when their DOM changes. Debounced 300ms so a
      // flurry of mutations (e.g. virtualized list scroll) coalesces.
      var __ytmObsTimer = null;
      function scheduleObs() {
        if (__ytmObsTimer) return;
        __ytmObsTimer = setTimeout(function() {
          __ytmObsTimer = null;
          decorateSidebar();
          scrapeVisibleTiles();
        }, 300);
      }
      function installObservers() {
        var sidebar = q('ytmusic-guide-renderer') || q('tp-yt-app-drawer#guide');
        var main = q('ytmusic-browse-response') || q('#content.ytmusic-app-layout');
        if (!sidebar && !main) return false;
        if (sidebar && !sidebar.__ytmObs) {
          sidebar.__ytmObs = true;
          new MutationObserver(scheduleObs).observe(sidebar, { childList: true, subtree: true });
        }
        if (main && !main.__ytmObs) {
          main.__ytmObs = true;
          new MutationObserver(scheduleObs).observe(main, { childList: true, subtree: true });
        }
        return !!(sidebar || main);
      }
      // Retry attach until both targets exist (YT mounts them asynchronously).
      var __ytmObsRetry = setInterval(function() {
        if (installObservers()) {
          clearInterval(__ytmObsRetry);
          scheduleObs();
        }
      }, 1000);
    })();
    """#
}
