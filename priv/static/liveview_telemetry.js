// ** AI Tooling Disclaimer **
// A large amount of this was created via an Agentic Coding session with Claude Opus 4.6.
// The methodology that I (@probably-not) followed was to give Claude a full spec of exactly what kind
// telemetry I need every page to emit, and then review what it was giving back to ensure that it was correct.
// Finally, at the end, since I am by no means a JavaScript or browser expert, I created a new separate incognito
// Claude Opus 4.6 session, passed in this codeblock, and asked it to deeply analyze it (essentially requesting an
// unbiased review with fresh eyes). This led to another series of fixes done by the main coding session, until the
// reviewer coding session had no more comments.

(function () {
  var spanId = 0;

  function emit(data) {
    console.log("__LIVELOAD||" + JSON.stringify(data));
  }

  // 1. LiveView lifecycle — keyed by kind, one in flight per kind
  var loadingSpans = {}; // kind -> {id, start}

  window.addEventListener("phx:page-loading-start", function (e) {
    // If a span of the same kind is already open (rapid double-navigation),
    // emit a canceled event before overwriting to avoid orphaned spans.
    var existing = loadingSpans[e.detail.kind];
    if (existing) {
      emit({
        kind: "phx_loading",
        phase: "canceled",
        info: e.detail.kind,
        span_id: existing.id,
        duration_ms: performance.now() - existing.start,
      });
    }
    var id = ++spanId;
    loadingSpans[e.detail.kind] = { id: id, start: performance.now() };
    emit({
      kind: "phx_loading",
      phase: "start",
      info: e.detail.kind,
      span_id: id,
    });
  });

  window.addEventListener("phx:page-loading-stop", function (e) {
    var span = loadingSpans[e.detail.kind];
    if (span) {
      emit({
        kind: "phx_loading",
        phase: "stop",
        info: e.detail.kind,
        span_id: span.id,
        duration_ms: performance.now() - span.start,
      });
      delete loadingSpans[e.detail.kind];
    }
  });

  // 2. Navigation events — point event, no span
  window.addEventListener("phx:navigate", function (e) {
    emit({ kind: "phx_navigate", href: e.detail.href, type: e.detail.type });
  });

  // 3. MutationObserver for phx-*-loading classes
  //    Keyed by element reference via WeakMap — handles multiple concurrent spans.
  //    WeakMap avoids leaking references to detached DOM elements.
  var tracked = [
    "phx-click-loading",
    "phx-submit-loading",
    "phx-change-loading",
  ];
  var classSpans = new WeakMap(); // element -> {cls -> {id, start}}
  var connectedEl = null; // the element that carries .phx-connected
  var connectedState = null; // null = never seen, "connected" = has class, "disconnected" = lost class
  var connectedLostAt = 0;

  var observer = new MutationObserver(function (mutations) {
    mutations.forEach(function (m) {
      if (m.type !== "attributes" || m.attributeName !== "class") return;
      var el = m.target;
      tracked.forEach(function (cls) {
        var has = el.classList.contains(cls);
        var spans = classSpans.get(el);
        var had = spans && spans[cls];

        if (has && !had) {
          // ADD — open a new span
          var id = ++spanId;
          if (!spans) {
            spans = {};
            classSpans.set(el, spans);
          }
          spans[cls] = { id: id, start: performance.now() };
          emit({
            kind: "loading_class",
            phase: "start",
            cls: cls,
            id: el.id || el.tagName,
            span_id: id,
          });
        } else if (!has && had) {
          // REMOVE — close the span, emit duration
          emit({
            kind: "loading_class",
            phase: "stop",
            cls: cls,
            id: el.id || el.tagName,
            span_id: had.id,
            duration_ms: performance.now() - had.start,
          });
          delete spans[cls];
        }
      });

      // 4. LiveView connection lifecycle — tracks initial connect, disconnect, reconnect.
      //    Uses a state machine: null → "connected" → "disconnected" → "connected" → ...
      //    SCOPED to the element that originally received .phx-connected — mutations on
      //    other elements (buttons, forms) are ignored for this check.
      //    State resets on full navigation (addInitScript re-runs the IIFE).
      if (el === connectedEl || connectedEl === null) {
        var isConnected = el.classList.contains("phx-connected");

        if (isConnected && connectedState === null) {
          connectedEl = el;
          connectedState = "connected";
          var initialSpan = loadingSpans["initial"];
          if (initialSpan) {
            emit({
              kind: "lv_connected",
              span_id: initialSpan.id,
              duration_ms: performance.now() - initialSpan.start,
            });
          }
        } else if (!isConnected && connectedState === "connected") {
          connectedState = "disconnected";
          connectedLostAt = performance.now();
          emit({ kind: "lv_disconnected" });
        } else if (isConnected && connectedState === "disconnected") {
          connectedState = "connected";
          emit({
            kind: "lv_reconnected",
            duration_ms: performance.now() - connectedLostAt,
          });
        }
      }
    });
  });

  // Defer until body exists
  (function start() {
    if (document.body) {
      emit({
        kind: "browser_telemetry_init",
        href: document.location.href,
      });

      observer.observe(document.body, {
        attributes: true,
        attributeFilter: ["class"],
        subtree: true,
      });
    } else {
      requestAnimationFrame(start);
    }
  })();
})();
