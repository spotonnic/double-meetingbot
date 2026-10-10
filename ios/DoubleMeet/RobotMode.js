// Robot mode for Google Meet, injected by the iPad app at document start.
//
// Shows the largest remote participant's video full-screen in an overlay on top of
// Meet, so the office sees the person, not Meet's toolbars and self-view. It does not
// depend on Meet's DOM structure: remote video is identified by its track object coming
// from an RTCPeerConnection (by identity, since a remote track can share the local id). If no remote video is live (lobby, cameras off) the overlay
// hides and Meet's own UI shows. Audio keeps playing through Meet.
//
// Control from native code: window.__doubleRobot.setEnabled(bool), .setFit('cover'|'contain'), .next(), .auto()
// Reports to native code via webkit.messageHandlers.doubleRobot: { active, name, count }
(function () {
  'use strict';
  if (window.__doubleRobot) return;

  var config = window.__doubleRobotConfig || {};
  var remoteTracks = new WeakSet();
  var remoteCount = 0;
  function markRemote(track) {
    if (track && !remoteTracks.has(track)) { remoteTracks.add(track); remoteCount++; }
  }
  var connections = [];

  // ---- 1. Learn which tracks are remote ----
  var NativePC = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (NativePC) {
    var WrappedPC = function (cfg, constraints) {
      var pc = new NativePC(cfg, constraints);
      connections.push(pc);
      pc.addEventListener('track', function (e) {
        markRemote(e.track);
      });
      pc.addEventListener('connectionstatechange', function () {
        if (pc.connectionState === 'closed') connections = connections.filter(function (c) { return c !== pc; });
      });
      return pc;
    };
    WrappedPC.prototype = NativePC.prototype;
    Object.keys(NativePC).forEach(function (k) { try { WrappedPC[k] = NativePC[k]; } catch (e) {} });
    try {
      Object.defineProperty(WrappedPC, 'name', { value: 'RTCPeerConnection' });
      Object.defineProperty(WrappedPC, 'generateCertificate', { value: NativePC.generateCertificate });
    } catch (e) {}
    window.RTCPeerConnection = WrappedPC;
    if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = WrappedPC;
  }

  function refreshRemoteTracks() {
    connections.forEach(function (pc) {
      try {
        pc.getReceivers().forEach(function (r) { markRemote(r.track); });
      } catch (e) {}
    });
  }

  function liveRemoteVideoTrack(video) {
    var stream = video.srcObject;
    if (!stream || typeof stream.getVideoTracks !== 'function') return null;
    var tracks = stream.getVideoTracks();
    for (var i = 0; i < tracks.length; i++) {
      var t = tracks[i];
      if (remoteTracks.has(t) && t.readyState === 'live' && !t.muted) return t;
    }
    return null;
  }

  function visibleArea(el) {
    if (el.videoWidth === 0 || el.paused) return 0;
    var r = el.getBoundingClientRect();
    var style = getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none' || Number(style.opacity) === 0) return 0;
    return Math.max(0, r.width) * Math.max(0, r.height);
  }

  // Best effort: a participant tile usually carries the person's name as short text.
  function nameFor(video) {
    var el = video;
    for (var i = 0; i < 8 && el; i++, el = el.parentElement) {
      if (el.hasAttribute && (el.hasAttribute('data-participant-id') || el.hasAttribute('data-requested-participant-id'))) {
        var lines = (el.innerText || '').split('\n').map(function (s) { return s.trim(); });
        for (var j = 0; j < lines.length; j++) {
          if (lines[j].length >= 2 && lines[j].length <= 40 && !/^(du|you)$/i.test(lines[j])) return lines[j];
        }
      }
    }
    return '';
  }

  // ---- 2. Overlay ----
  var overlay, stage, label;
  function buildOverlay() {
    overlay = document.createElement('div');
    overlay.id = 'double-robot-overlay';
    overlay.setAttribute('aria-hidden', 'true');
    overlay.style.cssText = [
      'position:fixed', 'inset:0', 'z-index:2147483646', 'background:#1A2332',
      'display:none', 'opacity:0', 'transition:opacity 400ms cubic-bezier(0.16,1,0.3,1)'
    ].join(';');
    stage = document.createElement('video');
    stage.autoplay = true; stage.muted = true; stage.playsInline = true;
    stage.setAttribute('playsinline', '');
    stage.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;background:#1A2332;object-fit:' + fit;
    label = document.createElement('div');
    label.style.cssText = [
      'position:absolute', 'left:24px', 'top:24px', 'padding:8px 12px', 'border-radius:8px',
      'background:rgba(26,35,50,0.8)', 'color:#F8F6F2', "font:500 15px/1.2 'DM Mono',ui-monospace,monospace",
      'letter-spacing:0.1em', 'text-transform:uppercase', 'display:none'
    ].join(';');
    overlay.appendChild(stage);
    overlay.appendChild(label);
    document.documentElement.appendChild(overlay);
  }

  var enabled = config.enabled !== false;
  var fit = config.fit === 'contain' ? 'contain' : 'cover';
  var current = null;          // source <video> currently shown
  var candidateSince = 0;
  var pinnedIndex = -1;        // set by next(); -1 = automatic
  var lastReport = '';

  function show(source) {
    if (stage.srcObject !== source.srcObject) {
      stage.srcObject = source.srcObject;
      var p = stage.play(); if (p && p.catch) p.catch(function () {});
    }
    current = source;
    var name = nameFor(source);
    label.textContent = name;
    label.style.display = name ? 'block' : 'none';
    if (overlay.style.display !== 'block') {
      overlay.style.display = 'block';
      requestAnimationFrame(function () { overlay.style.opacity = '1'; });
    }
  }

  function hide() {
    current = null;
    if (overlay.style.display === 'none') return;
    overlay.style.opacity = '0';
    overlay.style.display = 'none';
    stage.srcObject = null;
  }

  function report(active, name, count) {
    var msg = JSON.stringify({ active: active, name: name, count: count });
    if (msg === lastReport) return;
    lastReport = msg;
    try { window.webkit.messageHandlers.doubleRobot.postMessage({ active: active, name: name, count: count }); } catch (e) {}
  }

  function tick() {
    if (!overlay) return;
    refreshRemoteTracks();
    var candidates = Array.prototype.slice.call(document.querySelectorAll('video'))
      .filter(function (v) { return v !== stage && liveRemoteVideoTrack(v) && visibleArea(v) > 0; })
      .sort(function (a, b) { return visibleArea(b) - visibleArea(a); });

    if (!enabled || candidates.length === 0) {
      hide();
      report(false, '', candidates.length);
      return;
    }

    var pick;
    if (pinnedIndex >= 0) {
      pick = candidates[pinnedIndex % candidates.length];
    } else {
      pick = candidates[0];
      // Avoid flicker between similar tiles: switch only if clearly bigger for 1.5 s.
      if (current && candidates.indexOf(current) !== -1 && pick !== current) {
        var clearlyBigger = visibleArea(pick) > visibleArea(current) * 1.3;
        if (!clearlyBigger) { pick = current; candidateSince = 0; }
        else if (!candidateSince) { candidateSince = Date.now(); pick = current; }
        else if (Date.now() - candidateSince < 1500) { pick = current; }
        else { candidateSince = 0; }
      }
    }
    show(pick);
    report(true, label.textContent, candidates.length);
  }

  window.__doubleRobot = {
    setEnabled: function (on) { enabled = !!on; pinnedIndex = -1; tick(); },
    setFit: function (value) { fit = value === 'contain' ? 'contain' : 'cover'; if (stage) stage.style.objectFit = fit; },
    next: function () { pinnedIndex = pinnedIndex + 1; tick(); },
    auto: function () { pinnedIndex = -1; tick(); },
    state: function () { return { enabled: enabled, active: !!current, remoteTracks: remoteCount }; }
  };

  function start() {
    buildOverlay();
    setInterval(tick, 500);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
