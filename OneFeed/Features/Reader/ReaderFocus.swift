import Foundation

enum ReaderFocusMode: String, CaseIterable, Identifiable {
    case smart
    case paragraph
    case lines3
    case lines1
    case off

    var id: Self { self }

    var label: String {
        switch self {
        case .smart: "Smart"
        case .paragraph: "Paragraph"
        case .lines3: "3 lines"
        case .lines1: "1 line"
        case .off: "Off"
        }
    }
}

struct ReadingTrail: Codable, Equatable, Sendable {
    var articleID: UUID
    var blockIndex: Int
    var anchor: String
    var scrollRatio: Double
    var zoneY: Double
    var updatedAt: Date

    var isNearStart: Bool {
        blockIndex <= 0 && scrollRatio < 0.04
    }
}

enum ReadingTrailStore {
    private static let prefix = "readingTrail."

    static func load(articleID: UUID, defaults: UserDefaults = .standard) -> ReadingTrail? {
        guard let data = defaults.data(forKey: key(articleID)) else { return nil }
        return try? JSONDecoder().decode(ReadingTrail.self, from: data)
    }

    static func save(_ trail: ReadingTrail, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(trail) else { return }
        defaults.set(data, forKey: key(trail.articleID))
    }

    static func clear(articleID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(articleID))
    }

    private static func key(_ articleID: UUID) -> String {
        prefix + articleID.uuidString
    }
}

enum ReaderFocus {
    static let engineVersion = 2
    static let defaultZoneY = 0.37
    static let defaultIntensity = 0.55
    static let minimumZoneY = 0.28
    static let maximumZoneY = 0.52

    static func clampZone(_ value: Double) -> Double {
        min(maximumZoneY, max(minimumZoneY, value))
    }

    static func clampIntensity(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Previous / current / next opacity. Surrounding text never drops below 80%.
    static func opacities(intensity: Double) -> (previous: Double, near: Double, next: Double) {
        let amount = clampIntensity(intensity)
        return (
            previous: max(0.80, 1 - 0.20 * amount),
            near: max(0.85, 1 - 0.12 * amount),
            next: max(0.85, 1 - 0.15 * amount)
        )
    }

    static func snapshot(from value: Any?, articleID: UUID, fallbackZoneY: Double) -> ReadingTrail? {
        guard let dict = dictionary(value) else { return nil }
        let blockIndex = intValue(dict["blockIndex"]) ?? 0
        let scrollRatio = doubleValue(dict["scrollRatio"]) ?? 0
        let zoneY = clampZone(doubleValue(dict["zoneY"]) ?? fallbackZoneY)
        let anchor = (dict["anchor"] as? String) ?? ""
        return ReadingTrail(
            articleID: articleID,
            blockIndex: max(0, blockIndex),
            anchor: String(anchor.prefix(48)),
            scrollRatio: min(1, max(0, scrollRatio)),
            zoneY: zoneY,
            updatedAt: .now
        )
    }

    static func configuration(
        mode: ReaderFocusMode,
        intensity: Double,
        zoneY: Double,
        reduceMotion: Bool,
        trail: ReadingTrail?
    ) -> [String: Any] {
        var cfg: [String: Any] = [
            "mode": mode.rawValue,
            "intensity": clampIntensity(intensity),
            "zoneY": clampZone(zoneY),
            "reduceMotion": reduceMotion,
        ]
        if let trail, !trail.isNearStart {
            cfg["trail"] = [
                "blockIndex": trail.blockIndex,
                "anchor": trail.anchor,
                "scrollRatio": trail.scrollRatio,
            ] as [String: Any]
        }
        return cfg
    }

    static let pageCSS = """
        #onefeed-article { padding-bottom: max(88px, 52vh); }
        .onefeed-block { transition: opacity 180ms ease; }
        html.onefeed-reduce-motion .onefeed-block { transition: none; }
        html.onefeed-focus-hidden .onefeed-block { opacity: 1 !important; }
        #onefeed-marker {
          position: fixed;
          left: 5px;
          top: 0;
          width: 2px;
          border-radius: 1px;
          background: color-mix(in srgb, var(--link) 82%, transparent);
          opacity: 0;
          pointer-events: auto;
          touch-action: none;
          z-index: 4;
          will-change: transform, height;
          transition: opacity 160ms ease, height 160ms ease, transform 160ms ease;
        }
        #onefeed-marker::before {
          content: "";
          position: absolute;
          inset: -16px -8px -16px -12px;
        }
        html.onefeed-reduce-motion #onefeed-marker { transition: opacity 80ms ease; }
        #onefeed-line {
          position: fixed;
          left: 0;
          top: 0;
          height: 1px;
          background: color-mix(in srgb, var(--ink) 26%, transparent);
          opacity: 0;
          pointer-events: none;
          z-index: 3;
        }
        #onefeed-trail {
          position: fixed;
          left: 20px;
          top: 0;
          font: 650 11px/1.2 -apple-system, BlinkMacSystemFont, sans-serif;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--link);
          opacity: 0;
          pointer-events: none;
          z-index: 5;
          transition: opacity 200ms ease;
        }
        html.onefeed-reduce-motion #onefeed-trail { transition: opacity 80ms ease; }
        """

    static var pageScriptTag: String {
        "<script>\(pageScript)</script>"
    }

    static let pageScript = """
        window.OneFeedFocus = (function () {
          var BLOCKS = "p, li, h2, h3, blockquote, pre, figcaption";
          var state = {
            mode: "smart",
            intensity: 0.55,
            zoneY: 0.37,
            reduceMotion: false,
            hidden: true,
            dragging: false,
            touching: false,
            programmatic: false,
            pinned: null,
            lastY: 0,
            lastT: 0,
            velocity: 0,
            settleTimer: 0,
            currentBlock: 0,
            ticking: false
          };

          function articleRoot() {
            return document.getElementById("onefeed-article") || document.body;
          }

          function blocks() {
            return Array.prototype.slice.call(articleRoot().querySelectorAll(BLOCKS)).filter(function (el) {
              return (el.innerText || "").trim().length > 0;
            });
          }

          function ensureChrome() {
            var list = blocks();
            for (var i = 0; i < list.length; i += 1) {
              list[i].classList.add("onefeed-block");
              list[i].setAttribute("data-onefeed-index", String(i));
            }
            if (!document.getElementById("onefeed-marker")) {
              var marker = document.createElement("div");
              marker.id = "onefeed-marker";
              marker.setAttribute("aria-hidden", "true");
              document.body.appendChild(marker);
              bindMarker(marker);
            }
            if (!document.getElementById("onefeed-line")) {
              var line = document.createElement("div");
              line.id = "onefeed-line";
              line.setAttribute("aria-hidden", "true");
              document.body.appendChild(line);
            }
            if (!document.getElementById("onefeed-trail")) {
              var trail = document.createElement("div");
              trail.id = "onefeed-trail";
              trail.setAttribute("aria-hidden", "true");
              trail.textContent = "You stopped here";
              document.body.appendChild(trail);
            }
          }

          function bindMarker(marker) {
            marker.addEventListener("pointerdown", function (event) {
              event.preventDefault();
              event.stopPropagation();
              state.dragging = true;
              marker.setPointerCapture(event.pointerId);
            });
            marker.addEventListener("pointermove", function (event) {
              if (!state.dragging) return;
              state.zoneY = clamp(event.clientY / window.innerHeight, 0.28, 0.52);
              reveal();
              update();
            });
            function endDrag() { state.dragging = false; }
            marker.addEventListener("pointerup", endDrag);
            marker.addEventListener("pointercancel", endDrag);
          }

          function clamp(value, min, max) {
            return Math.min(max, Math.max(min, value));
          }

          function zoneLine() {
            return window.innerHeight * state.zoneY;
          }

          function hide() {
            state.hidden = true;
            document.documentElement.classList.add("onefeed-focus-hidden");
            document.documentElement.classList.remove("onefeed-focus-active");
            placeChrome(null, []);
          }

          function reveal() {
            if (state.mode === "off") return;
            state.hidden = false;
            document.documentElement.classList.remove("onefeed-focus-hidden");
            document.documentElement.classList.add("onefeed-focus-active");
            update();
          }

          function scheduleSettle() {
            if (state.settleTimer) window.clearTimeout(state.settleTimer);
            state.settleTimer = window.setTimeout(function () {
              if (state.touching || state.dragging) return;
              if (Math.abs(state.velocity) > 0.9) return;
              reveal();
            }, 260);
          }

          function onScroll() {
            var y = window.scrollY || 0;
            var t = performance.now();
            var dt = Math.max(1, t - state.lastT);
            state.velocity = (y - state.lastY) / dt;
            state.lastY = y;
            state.lastT = t;
            if (state.dragging || state.programmatic) return;
            if (state.pinned) state.pinned = null;
            var fast = Math.abs(state.velocity) > 0.9;
            if (fast || state.touching) {
              hide();
              scheduleSettle();
              return;
            }
            if (!state.hidden) requestUpdate();
            scheduleSettle();
          }

          function requestUpdate() {
            if (state.ticking) return;
            state.ticking = true;
            requestAnimationFrame(function () {
              state.ticking = false;
              update();
            });
          }

          function findBlock() {
            if (state.pinned && document.body.contains(state.pinned)) return state.pinned;
            var list = blocks();
            var y = zoneLine();
            var bandTop = window.innerHeight * Math.max(0.28, state.zoneY - 0.05);
            var bandBottom = window.innerHeight * Math.min(0.52, state.zoneY + 0.08);
            var best = null;
            var bestDist = Infinity;
            for (var i = 0; i < list.length; i += 1) {
              var rect = list[i].getBoundingClientRect();
              if (rect.bottom < 0 || rect.top > window.innerHeight) continue;
              if (rect.top <= y && rect.bottom >= y) return list[i];
              var mid = (rect.top + rect.bottom) / 2;
              if (mid < bandTop - 40 || mid > bandBottom + 40) continue;
              var dist = Math.abs(mid - y);
              if (dist < bestDist) {
                bestDist = dist;
                best = list[i];
              }
            }
            return best;
          }

          function lineRects(el) {
            var collected = [];
            var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null);
            var node;
            while (node = walker.nextNode()) {
              if (!(node.textContent || "").trim()) continue;
              var range = document.createRange();
              range.selectNodeContents(node);
              var rects = range.getClientRects();
              for (var i = 0; i < rects.length; i += 1) {
                var rect = rects[i];
                if (rect.height >= 4 && rect.width >= 8) collected.push(rect);
              }
            }
            collected.sort(function (a, b) { return a.top - b.top || a.left - b.left; });
            var lines = [];
            for (var j = 0; j < collected.length; j += 1) {
              var item = collected[j];
              var last = lines[lines.length - 1];
              if (last && Math.abs(last.top - item.top) < item.height * 0.45) {
                last.left = Math.min(last.left, item.left);
                last.right = Math.max(last.right, item.right);
                last.bottom = Math.max(last.bottom, item.bottom);
                last.width = last.right - last.left;
                last.height = last.bottom - last.top;
              } else {
                lines.push({
                  top: item.top,
                  left: item.left,
                  right: item.right,
                  bottom: item.bottom,
                  width: item.width,
                  height: item.height
                });
              }
            }
            if (!lines.length) {
              var box = el.getBoundingClientRect();
              lines.push({ top: box.top, left: box.left, right: box.right, bottom: box.bottom, width: box.width, height: box.height });
            }
            return lines;
          }

          function focusedLines(el) {
            var lines = lineRects(el);
            var count = 0;
            if (state.mode === "lines1" || state.mode === "smart") count = 1;
            else if (state.mode === "lines3") count = 3;
            if (!count) return lines;
            var y = zoneLine();
            if (state.pinned) y = el.getBoundingClientRect().top + 8;
            var idx = 0;
            var best = Infinity;
            for (var i = 0; i < lines.length; i += 1) {
              var mid = (lines[i].top + lines[i].bottom) / 2;
              var dist = Math.abs(mid - y);
              if (dist < best) {
                best = dist;
                idx = i;
              }
            }
            if (count === 1) return [lines[idx]];
            var start = Math.max(0, idx - 1);
            return lines.slice(start, start + 3);
          }

          function applyFade(current) {
            var list = blocks();
            var currentIndex = list.indexOf(current);
            var prev = Math.max(0.80, 1 - 0.20 * state.intensity);
            var near = Math.max(0.85, 1 - 0.12 * state.intensity);
            var next = Math.max(0.85, 1 - 0.15 * state.intensity);
            for (var i = 0; i < list.length; i += 1) {
              var el = list[i];
              var isCurrent = el === current;
              el.classList.toggle("is-current", isCurrent);
              el.classList.toggle("is-near", Math.abs(i - currentIndex) === 1);
              if (state.hidden || state.mode === "off" || !current) {
                el.style.opacity = "";
                continue;
              }
              if (isCurrent) el.style.opacity = "1";
              else if (Math.abs(i - currentIndex) === 1) el.style.opacity = String(near);
              else if (i < currentIndex) el.style.opacity = String(prev);
              else el.style.opacity = String(next);
            }
          }

          function placeChrome(el, lines) {
            var marker = document.getElementById("onefeed-marker");
            var underline = document.getElementById("onefeed-line");
            if (!marker) return;
            if (state.hidden || state.mode === "off" || !el) {
              marker.style.opacity = "0";
              if (underline) underline.style.opacity = "0";
              return;
            }
            var top;
            var height;
            if ((state.mode === "smart" || state.mode === "lines1" || state.mode === "lines3") && lines && lines.length) {
              top = lines[0].top;
              height = lines[lines.length - 1].bottom - lines[0].top;
            } else {
              var box = el.getBoundingClientRect();
              top = box.top;
              height = box.height;
            }
            marker.style.opacity = "1";
            marker.style.transform = "translateY(" + Math.round(top) + "px)";
            marker.style.height = Math.max(16, Math.round(height)) + "px";
            if (underline && (state.mode === "smart" || state.mode === "lines1") && lines && lines[0]) {
              underline.style.opacity = "0.7";
              underline.style.transform = "translate(" + Math.round(lines[0].left) + "px," + Math.round(lines[0].bottom - 1) + "px)";
              underline.style.width = Math.round(lines[0].width) + "px";
            } else if (underline) {
              underline.style.opacity = "0";
            }
          }

          function update() {
            if (state.mode === "off") {
              applyFade(null);
              placeChrome(null, []);
              return;
            }
            var el = findBlock();
            if (!el) return;
            var lines = focusedLines(el);
            state.currentBlock = Number(el.getAttribute("data-onefeed-index") || 0);
            applyFade(el);
            placeChrome(el, lines);
          }

          function selectedText() {
            var selection = window.getSelection && window.getSelection();
            return selection ? String(selection).trim() : "";
          }

          function onTap(event) {
            if (state.mode === "off" || state.dragging) return;
            if (event.target.closest && event.target.closest("a, button, input, textarea")) return;
            if (selectedText()) return;
            var el = event.target.closest ? event.target.closest(BLOCKS) : null;
            if (!el || !articleRoot().contains(el)) return;
            state.pinned = el;
            reveal();
          }

          function showResume(el) {
            var banner = document.getElementById("onefeed-trail");
            if (!banner || !el) return;
            var box = el.getBoundingClientRect();
            banner.style.transform = "translateY(" + Math.max(12, box.top - 26) + "px)";
            banner.style.opacity = "1";
            window.setTimeout(function () { banner.style.opacity = "0"; }, 1400);
          }

          function restore(trail) {
            ensureChrome();
            var list = blocks();
            var el = list[trail.blockIndex];
            if (trail.anchor) {
              for (var i = 0; i < list.length; i += 1) {
                if ((list[i].innerText || "").indexOf(trail.anchor) !== -1) {
                  el = list[i];
                  break;
                }
              }
            }
            if (el) {
              state.programmatic = true;
              var top = el.getBoundingClientRect().top + window.scrollY;
              window.scrollTo(0, Math.max(0, top - window.innerHeight * state.zoneY + 10));
              state.pinned = el;
              reveal();
              showResume(el);
              window.setTimeout(function () {
                state.programmatic = false;
                if (state.pinned === el) state.pinned = null;
              }, 1600);
            } else if (typeof trail.scrollRatio === "number") {
              state.programmatic = true;
              var max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
              window.scrollTo(0, max * trail.scrollRatio);
              window.setTimeout(function () { state.programmatic = false; }, 400);
            }
          }

          function configure(cfg) {
            if (!cfg) return;
            ensureChrome();
            if (cfg.mode) state.mode = cfg.mode;
            if (typeof cfg.intensity === "number") state.intensity = clamp(cfg.intensity, 0, 1);
            if (typeof cfg.zoneY === "number") state.zoneY = clamp(cfg.zoneY, 0.28, 0.52);
            if (typeof cfg.reduceMotion === "boolean") {
              state.reduceMotion = cfg.reduceMotion;
              document.documentElement.classList.toggle("onefeed-reduce-motion", cfg.reduceMotion);
            }
            if (state.mode === "off") {
              hide();
              applyFade(null);
              return;
            }
            if (cfg.trail) restore(cfg.trail);
            else if (!state.hidden) update();
            else scheduleSettle();
          }

          function snapshot() {
            var list = blocks();
            var el = list[state.currentBlock];
            var text = el ? String(el.innerText || "").replace(/\\s+/g, " ").trim() : "";
            var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            return {
              blockIndex: state.currentBlock || 0,
              anchor: text.slice(0, 48),
              scrollRatio: (window.scrollY || 0) / max,
              zoneY: state.zoneY
            };
          }

          document.addEventListener("click", onTap, true);
          document.addEventListener("touchstart", function () {
            state.touching = true;
            if (!state.dragging && state.mode !== "off") hide();
          }, { passive: true });
          document.addEventListener("touchend", function () {
            state.touching = false;
            scheduleSettle();
          }, { passive: true });
          window.addEventListener("scroll", onScroll, { passive: true });
          ensureChrome();

          return { configure: configure, snapshot: snapshot, hide: hide, show: reveal };
        })();
        """

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let dict = value as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, item) in dict {
                if let string = key as? String { mapped[string] = item }
            }
            return mapped
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Double { return Int(number) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}
