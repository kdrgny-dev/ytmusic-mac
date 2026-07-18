// Tests the shuffle keeper's retry logic by extracting the real ensureShuffle
// source out of PlayerBridge.swift and running it against a fake DOM + clock.
// The bug this guards: a click on YT's shuffle button silently no-ops while
// the player is booting, so clicking once left shuffle off for ~10s.

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const SRC = path.join(__dirname, '../../Sources/YTMusicMac/PlayerBridge.swift');
const swift = fs.readFileSync(SRC, 'utf8');

const start = swift.indexOf('var __ytmShuffleRun = 0;');
const end = swift.indexOf('\n      }', swift.indexOf('function ensureShuffle('));
assert.ok(start > 0 && end > start, 'could not extract ensureShuffle from PlayerBridge.swift');
const source = swift.slice(start, end + '\n      }'.length);

/// Builds an isolated run of the extracted code with a controllable world.
function harness({ clicksNeeded = 1, buttonAfter = 0, alwaysShuffle = true,
                   radioPage = false, graceAgo = 999999 } = {}) {
  const state = { on: false, clicks: 0, now: 0 };
  let timers = [];

  const win = {
    __ytmAlwaysShuffle: alwaysShuffle,
    __ytmRadioPage: radioPage,
    __ytmShuffleSettled: false,
    __ytmUserToggledShuffleAt: -graceAgo,
    __ytmSelfClickingShuffle: false
  };
  const ctx = {
    window: win,
    Date: { now: () => state.now },
    setTimeout: (fn, ms) => timers.push({ at: state.now + ms, fn }),
    shuffleDiag: () => {},
    attachShuffleClickListener: () => {},
    shuffleIsOn: () => state.on,
    findShuffleBtn: () => state.now >= buttonAfter ? {
      click() {
        state.clicks++;
        // YT ignores clicks until its player is ready.
        if (state.clicks >= clicksNeeded) state.on = true;
      }
    } : null
  };

  const names = Object.keys(ctx);
  const fn = new Function(...names, source + '\nreturn ensureShuffle;');
  const ensureShuffle = fn(...names.map(n => ctx[n]));

  return {
    state,
    call: (why) => ensureShuffle(why),
    // Run the fake clock forward, firing due timers in order.
    advance(ms) {
      const target = state.now + ms;
      while (true) {
        const due = timers.filter(t => t.at <= target).sort((a, b) => a.at - b.at)[0];
        if (!due) break;
        timers = timers.filter(t => t !== due);
        state.now = due.at;
        due.fn();
      }
      state.now = target;
    }
  };
}

const tests = {
  'retries until a swallowed click finally takes'() {
    const h = harness({ clicksNeeded: 4 });
    h.call('setAlwaysShuffle');
    h.advance(5000);
    assert.strictEqual(h.state.on, true, 'shuffle should end up on');
    assert.ok(h.state.clicks >= 4, `expected retries, got ${h.state.clicks} clicks`);
  },

  'stops clicking once shuffle is on'() {
    const h = harness({ clicksNeeded: 1 });
    h.call('setAlwaysShuffle');
    h.advance(10000);
    assert.strictEqual(h.state.clicks, 1, 'must not keep toggling after it sticks');
  },

  'waits for the button to appear, then turns it on'() {
    const h = harness({ clicksNeeded: 1, buttonAfter: 3000 });
    h.call('loadedmetadata');
    h.advance(6000);
    assert.strictEqual(h.state.on, true, 'a late-mounting button must still be handled');
  },

  'gives up after the deadline instead of clicking forever'() {
    const h = harness({ clicksNeeded: Infinity });
    h.call('setAlwaysShuffle');
    h.advance(120000);
    assert.ok(h.state.clicks < 60, `runaway loop: ${h.state.clicks} clicks`);
  },

  'does nothing when always-shuffle is off'() {
    const h = harness({ alwaysShuffle: false });
    h.call('setAlwaysShuffle');
    h.advance(10000);
    assert.strictEqual(h.state.clicks, 0);
  },

  'never touches shuffle on a radio page'() {
    // Toggling shuffle makes YT re-draw the queue, which skips the playing
    // track. A radio is already a shuffled mix, so the keeper stays out.
    const h = harness({ radioPage: true });
    h.call('loadedmetadata');
    h.advance(30000);
    assert.strictEqual(h.state.clicks, 0, 'radio must never be reshuffled');
  },

  'settles once per page and ignores later resets by YT'() {
    // Re-enabling shuffle every time YT turns it off costs a skipped track
    // each time — that was the "radio jumps every 3-5s" bug.
    const h = harness({ clicksNeeded: 1 });
    h.call('setAlwaysShuffle');
    h.advance(2000);
    assert.strictEqual(h.state.on, true);
    h.state.on = false;              // YT turns it back off mid-session
    h.call('loadedmetadata');
    h.advance(30000);
    assert.strictEqual(h.state.clicks, 1, 'must not fight YT after settling');
    assert.strictEqual(h.state.on, false, 'later resets are left alone');
  },

  'respects a recent manual toggle'() {
    const h = harness({ graceAgo: 5000 });
    h.call('attrchange');
    h.advance(10000);
    assert.strictEqual(h.state.clicks, 0, 'user turning shuffle off must hold');
  },

  'lets the newest call supersede an in-flight retry loop'() {
    const h = harness({ clicksNeeded: 3 });
    h.call('setAlwaysShuffle');
    h.advance(500);
    h.call('loadedmetadata');
    h.advance(5000);
    assert.strictEqual(h.state.on, true);
    assert.ok(h.state.clicks <= 6, `duelling loops double-clicked: ${h.state.clicks}`);
  }
};

let failed = 0;
for (const [name, run] of Object.entries(tests)) {
  try {
    run();
    console.log(`  ok  ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL ${name}\n       ${e.message}`);
  }
}
console.log(`\nshuffle keeper: ${Object.keys(tests).length - failed}/${Object.keys(tests).length} passed`);
process.exit(failed ? 1 : 0);
