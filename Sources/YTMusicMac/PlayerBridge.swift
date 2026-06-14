import Foundation

enum PlayerBridge {

    // ---------- CSS features (toggleable from native) ----------

    /// Hides YT Music's Premium upsell banners and friends.
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
            ("playerLayout", playerLayoutCSS, true)
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
      setInterval(send, 1500);

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
    })();
    """#
}
