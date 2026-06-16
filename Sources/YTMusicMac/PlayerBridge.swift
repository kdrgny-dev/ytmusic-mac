import Foundation

enum PlayerBridge {

    // ---------- CSS features (toggleable from native) ----------

    /// Hides YT Music's Premium upsell banners and forces the dynamic
    /// art-tinted background gradient (which spans the whole browse area)
    /// to the theme's base background color instead. Selectors are narrow
    /// and known — wildcard patterns caused regressions last time.
    static let hidePromosCSS = #"""
    ytmusic-premium-promo-renderer,
    ytmusic-mealbar-promo-renderer,
    ytmusic-statement-banner-renderer,
    ytmusic-you-there-renderer,
    ytmusic-popup-container ytmusic-promo-renderer,
    tp-yt-paper-dialog#mealbar-promo,
    tp-yt-paper-dialog#consent-bump-v2-lightbox {
      display: none !important;
    }
    /* Flatten the art-derived gradient backdrop to the theme color */
    .background-gradient.ytmusic-browse-response,
    ytmusic-browse-response .background-gradient {
      background: var(--yt-spec-base-background, #030303) !important;
      background-image: none !important;
      background-color: var(--yt-spec-base-background, #030303) !important;
      opacity: 1 !important;
    }
    ytmusic-background-renderer {
      display: none !important;
    }
    """#

    /// Stacked playlist header — Spotify-style. Targets the actual DOM:
    /// `ytmusic-two-column-browse-results-renderer` splits a detail page into
    /// `#primary` (header) and `#secondary` (track list) columns AND uses
    /// CSS grid plus sticky positioning. We collapse the grid to a single
    /// column, kill all sticky/fixed positioning in the chain, then rebuild
    /// the header as cover-left + info-right.
    static let stackedHeaderCSS = #"""
    /* ============================================================
       1. Page-level: collapse the two-column split into one column.
       Use display:flex column AND grid overrides AND child flex-basis
       so we win regardless of whether YT's CSS uses grid or flex.
       ============================================================ */
    html body ytmusic-browse-response ytmusic-two-column-browse-results-renderer,
    ytmusic-browse-response ytmusic-two-column-browse-results-renderer,
    ytmusic-two-column-browse-results-renderer {
      display: flex !important;
      flex-direction: column !important;
      flex-wrap: wrap !important;
      grid-template-columns: 1fr !important;
      grid-template-rows: auto auto !important;
      grid-template-areas: none !important;
      align-items: stretch !important;
    }

    ytmusic-two-column-browse-results-renderer > #primary,
    ytmusic-two-column-browse-results-renderer > #secondary {
      display: block !important;
      position: static !important;
      width: 100% !important;
      max-width: none !important;
      min-width: 0 !important;
      flex: 0 0 auto !important;
      flex-basis: 100% !important;
      grid-column: 1 / -1 !important;
      grid-row: auto !important;
      grid-area: auto !important;
      margin: 0 !important;
      padding: 0 !important;
      top: auto !important; left: auto !important;
      right: auto !important; bottom: auto !important;
      transform: none !important;
    }

    /* Kill any max-width / margin constraints in the section-list chain so
       the header spans the same width as the track list below it. */
    ytmusic-two-column-browse-results-renderer ytmusic-section-list-renderer,
    ytmusic-two-column-browse-results-renderer ytmusic-section-list-renderer > #contents,
    ytmusic-editable-playlist-detail-header-renderer {
      width: 100% !important;
      max-width: none !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
      padding-left: 0 !important;
      padding-right: 0 !important;
    }

    /* ============================================================
       2. Header chain: nuke sticky/fixed/absolute positioning so
       nothing floats over the page.
       ============================================================ */
    ytmusic-editable-playlist-detail-header-renderer,
    ytmusic-responsive-header-renderer,
    ytmusic-responsive-header-renderer > *,
    ytmusic-responsive-header-renderer ytmusic-thumbnail-renderer,
    ytmusic-responsive-header-renderer ytmusic-thumbnail-renderer *,
    ytmusic-responsive-header-renderer yt-img-shadow,
    ytmusic-responsive-header-renderer yt-img-shadow img {
      position: static !important;
      top: auto !important; left: auto !important;
      right: auto !important; bottom: auto !important;
      inset: auto !important;
      transform: none !important;
      float: none !important;
    }
    /* Hide empty dom-if templates that would otherwise steal grid cells */
    ytmusic-responsive-header-renderer > dom-if {
      display: none !important;
    }

    /* ============================================================
       3. Header layout: 3-column grid — cover left, info middle,
       optional video clip on the right (added by JS when enabled).
       Attribute selector boosts specificity to beat YT's own rules.
       ============================================================ */
    html body ytmusic-responsive-header-renderer[is-playlist-detail-page],
    ytmusic-responsive-header-renderer[is-playlist-detail-page],
    ytmusic-responsive-header-renderer {
      display: grid !important;
      grid-template-columns: 220px 1fr !important;
      grid-template-rows: auto !important;
      grid-auto-rows: auto !important;
      column-gap: 24px !important;
      row-gap: 4px !important;
      align-items: start !important;
      justify-items: start !important;
      padding: 24px 32px !important;
      width: 100% !important;
      max-width: 100% !important;
      min-height: 0 !important;
      height: auto !important;
      background: transparent !important;
    }

    /* Cover in column 1. Use span 10 — covers the ~6 info children we know
       about without leaving empty rows that push the cover to the bottom. */
    ytmusic-responsive-header-renderer > ytmusic-thumbnail-renderer.thumbnail {
      grid-column: 1 !important;
      grid-row: 1 / span 10 !important;
      width: 220px !important;
      height: 220px !important;
      margin: 0 !important;
      align-self: start !important;
      justify-self: start !important;
    }
    ytmusic-responsive-header-renderer > .thumbnail-edit-button-wrapper {
      grid-column: 1 !important;
      grid-row: 1 / span 10 !important;
      align-self: end !important;
      justify-self: end !important;
      position: relative !important;
      margin: 0 8px 8px 0 !important;
      z-index: 2 !important;
    }
    ytmusic-responsive-header-renderer yt-img-shadow,
    ytmusic-responsive-header-renderer yt-img-shadow #img,
    ytmusic-responsive-header-renderer yt-img-shadow img {
      width: 220px !important;
      height: 220px !important;
      max-width: 220px !important;
      max-height: 220px !important;
      display: block !important;
      margin: 0 !important;
    }

    /* Info elements in column 2, top-aligned and left-aligned */
    ytmusic-responsive-header-renderer > h1,
    ytmusic-responsive-header-renderer > .facepile-container,
    ytmusic-responsive-header-renderer > .subtitle-wrapper,
    ytmusic-responsive-header-renderer > .second-subtitle-container,
    ytmusic-responsive-header-renderer > #header-description,
    ytmusic-responsive-header-renderer > #countdown-timer,
    ytmusic-responsive-header-renderer > #action-buttons {
      grid-column: 2 !important;
      justify-self: start !important;
      align-self: start !important;
      text-align: left !important;
      margin: 0 !important;
      padding: 0 !important;
      width: auto !important;
      max-width: 100% !important;
    }
    ytmusic-responsive-header-renderer > h1 {
      font-size: 32px !important;
      line-height: 1.1 !important;
      margin: 0 !important;
      padding: 0 !important;
    }
    ytmusic-responsive-header-renderer > #action-buttons {
      display: flex !important;
      flex-direction: row !important;
      justify-content: flex-start !important;
      gap: 8px !important;
      margin-top: 8px !important;
    }
    """#

    /// Compact mode: narrower sidebar, tighter row paddings, hides the
    /// "K G" subtitle on user playlists. Lets more content fit on screen.
    static let compactModeCSS = #"""
    /* Sidebar width — YT Music drives this via a Polymer variable AND a
       hard-coded width on the drawer element. Override every reasonable
       hook we can find. */
    ytmusic-app-layout {
      --ytmusic-nav-bar-height: 56px !important;
      --ytmusic-guide-width: 200px !important;
    }
    ytmusic-app-layout #guide,
    ytmusic-app-layout tp-yt-app-drawer#guide,
    tp-yt-app-drawer#guide.ytmusic-app-layout {
      width: 200px !important;
      min-width: 200px !important;
      max-width: 200px !important;
    }
    ytmusic-app-layout #guide .draggable-area,
    ytmusic-guide-renderer {
      width: 100% !important;
    }
    ytmusic-guide-entry-renderer {
      padding-top: 2px !important;
      padding-bottom: 2px !important;
    }
    /* Hide "K G" subtitles under playlist names — name is enough */
    ytmusic-guide-entry-renderer .subtitle.ytmusic-guide-entry-renderer,
    ytmusic-guide-entry-renderer yt-formatted-string.subtitle {
      display: none !important;
    }
    /* Tighter track rows everywhere */
    ytmusic-responsive-list-item-renderer {
      padding-top: 4px !important;
      padding-bottom: 4px !important;
    }
    /* Smaller home-page section paddings */
    ytmusic-carousel-shelf-renderer,
    ytmusic-shelf-renderer {
      padding-top: 12px !important;
      padding-bottom: 12px !important;
    }
    """#

    /// Zebra striping on list rows (playlist tracks, albums, search results)
    /// for easier scanning.
    static let zebraStripingCSS = #"""
    ytmusic-responsive-list-item-renderer:nth-of-type(even) {
      background: rgba(255, 255, 255, 0.035) !important;
    }
    ytmusic-responsive-list-item-renderer:hover {
      background: rgba(255, 255, 255, 0.08) !important;
    }
    """#

    /// Player-bar: song info on the left, transport controls centered,
    /// secondary controls on the right (Spotify-style).
    static let playerLayoutCSS = #"""
    ytmusic-app ytmusic-player-bar {
      display: grid !important;
      grid-template-columns: 1fr auto 1fr !important;
      grid-template-areas: "info transport extras" !important;
      align-items: center !important;
      gap: 16px !important;
    }
    ytmusic-app ytmusic-player-bar .middle-controls.ytmusic-player-bar {
      grid-area: info !important;
      justify-self: start !important;
      width: auto !important;
      max-width: 100% !important;
      min-width: 0 !important;
      flex: 0 1 auto !important;
    }
    ytmusic-app ytmusic-player-bar .left-controls.ytmusic-player-bar {
      grid-area: transport !important;
      justify-self: center !important;
      width: auto !important;
      flex: 0 0 auto !important;
    }
    ytmusic-app ytmusic-player-bar .right-controls.ytmusic-player-bar {
      grid-area: extras !important;
      justify-self: end !important;
      width: auto !important;
      flex: 0 1 auto !important;
    }
    """#

    /// Bootstrap script: installs each feature as a separate `<style id="__ytm_<name>">`
    /// element. `window.__ytmSetFeature(name, on)` flips `style.disabled` to enable
    /// or disable a feature live without reloading the page.
    static var cssBootstrapScript: String {
        let features: [(name: String, css: String, default: Bool)] = [
            ("hidePromos", hidePromosCSS, true),
            ("playerLayout", playerLayoutCSS, true),
            ("zebraStriping", zebraStripingCSS, true),
            ("compactMode", compactModeCSS, false),
            ("stackedHeader", stackedHeaderCSS, false)
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

      function likeStatus() {
        try {
          var el = q('ytmusic-like-button-renderer');
          return el ? el.getAttribute('like-status') : null;
        } catch (e) { return null; }
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
            volume: v ? v.volume : 1,
            title: titleEl ? titleEl.textContent.trim() : '',
            artist: artistEl ? artistEl.textContent.trim() : '',
            artwork: artEl ? artEl.src : '',
            liked: likeStatus() === 'LIKE',
            disliked: likeStatus() === 'DISLIKE'
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
        ['play', 'pause', 'seeked', 'ratechange', 'volumechange',
         'loadedmetadata', 'durationchange', 'ended'].forEach(function(ev) {
          v.addEventListener(ev, sendSoon);
        });
        sendSoon();
        return true;
      }
      // Try to attach until the <video> element appears (YT mounts it after
      // user interaction). Stops polling once attached.
      var __ytmAttachTimer = setInterval(function() {
        if (attachVideoListeners()) clearInterval(__ytmAttachTimer);
      }, 800);
      // Safety net for state that has no DOM event: title/artist/artwork
      // change on track switch (loadedmetadata catches most), like/dislike
      // clicks from inside YT's UI, etc. 4s is plenty for these.
      setInterval(send, 4000);

      window.__ytmCmd = function(cmd, arg) {
        try {
          var v = q('video');
          if (cmd === 'playpause') { if (v) { v.paused ? v.play() : v.pause(); } return; }
          if (cmd === 'seek')      { if (v && typeof arg === 'number') v.currentTime = arg; return; }
          if (cmd === 'volume')    { if (v && typeof arg === 'number') v.volume = Math.max(0, Math.min(1, arg)); return; }
          if (cmd === 'like') {
            var like = q('ytmusic-like-button-renderer #button-shape-like') ||
                       q('ytmusic-like-button-renderer button[aria-label*="like" i]:not([aria-label*="dislike" i])');
            if (like) like.click();
            return;
          }
          if (cmd === 'dislike') {
            var dis = q('ytmusic-like-button-renderer #button-shape-dislike') ||
                      q('ytmusic-like-button-renderer button[aria-label*="dislike" i]');
            if (dis) dis.click();
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

      window.__ytmFocusSearch = function() {
        try {
          var input = q('ytmusic-search-box input') || q('input#input');
          if (input) { input.focus(); input.select && input.select(); }
        } catch (e) {}
      };

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
      // yt-navigate-finish is YT's canonical SPA-navigation event and covers
      // virtually all transitions. We keep a slow URL-poll as a safety net
      // (some Polymer redirects don't fire it) but at 2s instead of 800ms.
      var __ytmLastUrl = location.href;
      setInterval(function() {
        if (location.href !== __ytmLastUrl) {
          __ytmLastUrl = location.href;
          tryExtract();
        }
      }, 2000);
      // Sidebar/tile refresh: was 2500ms (heavy querySelectorAll over the
      // whole page). 6000ms is still responsive enough for lazy-loaded
      // shelves but cuts background CPU ~2.4x.
      setInterval(function() {
        decorateSidebar();
        scrapeVisibleTiles();
      }, 6000);
    })();
    """#
}
