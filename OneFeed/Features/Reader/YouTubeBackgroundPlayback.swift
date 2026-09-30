import Foundation
import WebKit

/// YouTube-scoped background playback experiment and diagnostics.
enum YouTubeBackgroundPlayback {
    static let messageName = "oneFeedMedia"

    @MainActor
    static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        controller.add(YouTubeMediaDiagnosticHandler(), contentWorld: .page, name: messageName)
        controller.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))
        return controller
    }

    /// Starts the JavaScript command synchronously from the scene callback, before
    /// awaiting WebKit's native state query.
    @MainActor
    static func command(_ name: String, on page: WebPage) async -> Any? {
        let source = "return window.__oneFeedPlayback && window.__oneFeedPlayback.\(name)();"
        do {
            return try await page.callJavaScript(source, contentWorld: .page)
        } catch {
            NSLog("[OneFeed][YouTubeJS] command=%@ error=%@", name, error.localizedDescription)
            return nil
        }
    }

    private static let script = #"""
    (() => {
        const host = location.hostname.toLowerCase();
        const youtubeHost = host === 'youtube.com' || host.endsWith('.youtube.com')
            || host === 'youtube-nocookie.com' || host.endsWith('.youtube-nocookie.com')
            || host === 'youtu.be';
        if (!youtubeHost || window.__oneFeedPlayback) return;

        const hiddenDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'hidden');
        const visibilityDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
        const originalHidden = () => {
            try { return hiddenDescriptor?.get ? hiddenDescriptor.get.call(document) : document.hidden; }
            catch (_) { return null; }
        };
        const originalVisibility = () => {
            try { return visibilityDescriptor?.get ? visibilityDescriptor.get.call(document) : 'unknown'; }
            catch (_) { return 'unknown'; }
        };
        try {
            Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
            Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
        } catch (error) {
            // Keep working with the original getters if this WebKit page disallows an own property.
        }

        const records = new WeakMap();
        const tracked = new Set();
        const maxTracked = 16;
        const retryDelays = [0, 120, 300, 650, 1200, 2200, 4000];
        let nextID = 1;
        let nativeBackgroundIntent = false;
        let intentArmed = false;
        let frameHadPlayback = false;
        let playerRoot = null;
        let retryTimers = [];
        let observer = null;
        let userPausedDuringBackground = false;

        const actualHidden = () => originalHidden() === true || originalVisibility() === 'hidden';
        const playerFor = element => element.closest('ytd-player, #movie_player, .html5-video-player');
        const cleanStack = stack => (stack || '').split('\n').slice(1, 6).map(line => {
            const match = line.match(/\bat\s+([^\s(]+)/) || line.match(/^\s*([^\s(]+)/);
            return match ? match[1].slice(0, 80) : 'anonymous';
        });
        const send = (event, media, extra = {}) => {
            try {
                const record = media ? records.get(media) : null;
                const payload = {
                    event,
                    mediaID: record?.id ?? null,
                    paused: media ? Boolean(media.paused) : null,
                    ended: media ? Boolean(media.ended) : null,
                    readyState: media ? Number(media.readyState) : null,
                    networkState: media ? Number(media.networkState) : null,
                    currentTime: media ? Math.round(Number(media.currentTime || 0) * 10) / 10 : null,
                    errorCode: media?.error ? Number(media.error.code) : null,
                    everPlayed: record?.everPlayed ?? null,
                    resumeIntent: record?.resumeIntent ?? null,
                    actualHidden: actualHidden(),
                    actualVisibility: String(originalVisibility()).slice(0, 16),
                    maskedVisibility: String(document.visibilityState).slice(0, 16),
                    ...extra
                };
                if (window.webkit?.messageHandlers?.oneFeedMedia) {
                    window.webkit.messageHandlers.oneFeedMedia.postMessage(payload);
                }
            } catch (_) { /* Diagnostics must never affect playback. */ }
        };

        const cancelRetries = () => {
            retryTimers.forEach(clearTimeout);
            retryTimers = [];
            observer?.disconnect();
            observer = null;
        };

        const clearIntent = (reason = 'reader-closed') => {
            nativeBackgroundIntent = false;
            intentArmed = false;
            cancelRetries();
            for (const media of tracked) {
                const record = records.get(media);
                if (record) record.resumeIntent = false;
            }
            userPausedDuringBackground = reason === 'media-session-pause';
            send('intent-cleared', null, { reason });
        };

        const resumeOne = async media => {
            const record = records.get(media);
            if (!record?.resumeIntent || !record.everPlayed || media.ended || !media.paused || record.resumePending) return;
            record.resumePending = true;
            send('resume-attempt', media);
            try {
                await media.play();
                send('resume-resolved', media);
            } catch (error) {
                send('resume-rejected', media, { errorName: String(error?.name || 'Error').slice(0, 48) });
            } finally {
                record.resumePending = false;
            }
        };

        const scan = () => {
            if (!intentArmed) return;
            for (const media of document.querySelectorAll('video, audio')) {
                let record = records.get(media);
                if (!record && tracked.size < maxTracked) {
                    const root = playerFor(media);
                    const authorizedRoot = [...tracked].some(previous => {
                        const previousRecord = records.get(previous);
                        return previousRecord?.resumeIntent && previousRecord.playerRoot === root;
                    });
                    if (!frameHadPlayback || !root || root !== playerRoot || !authorizedRoot) continue;
                    record = { id: `m${nextID++}`, everPlayed: true, activeCandidate: false, resumeIntent: true, playerRoot: root, resumePending: false, lastTimeUpdate: 0 };
                    records.set(media, record);
                    tracked.add(media);
                    bindMedia(media, record);
                    send('replacement-tracked', media);
                }
                if (record?.resumeIntent) void resumeOne(media);
            }
        };

        const scheduleRetries = (reset = false) => {
            if (reset) cancelRetries();
            if (retryTimers.length || !intentArmed) return;
            retryDelays.forEach(delay => {
                retryTimers.push(setTimeout(() => {
                    if (intentArmed) scan();
                    if (delay === retryDelays[retryDelays.length - 1]) {
                        observer?.disconnect();
                        observer = null;
                    }
                }, delay));
            });
            if (window.MutationObserver) {
                observer = new MutationObserver(() => scan());
                observer.observe(document.documentElement, { childList: true, subtree: true });
            }
        };

        const bindMedia = (media, record) => {
            const onMediaEvent = event => {
                if (event.type === 'timeupdate') {
                    const now = Date.now();
                    if (now - record.lastTimeUpdate < 5000) return;
                    record.lastTimeUpdate = now;
                }
                if (event.type === 'play' || event.type === 'playing') {
                    record.everPlayed = true;
                    record.activeCandidate = true;
                    record.playerRoot = playerFor(media) || record.playerRoot;
                    frameHadPlayback = true;
                    playerRoot = playerFor(media) || playerRoot;
                    if (nativeBackgroundIntent && record.resumeIntent) scheduleRetries();
                } else if (event.type === 'pause') {
                    if (record.everPlayed && !userPausedDuringBackground && (nativeBackgroundIntent || actualHidden())) {
                        record.resumeIntent = true;
                        send('pause-event', media, { cause: 'background' });
                        scheduleRetries();
                        return;
                    }
                    send('pause-event', media, { cause: 'foreground' });
                    record.activeCandidate = false;
                    record.resumeIntent = false;
                } else if (event.type === 'ended' || event.type === 'emptied') {
                    record.activeCandidate = false;
                    record.resumeIntent = false;
                }
                send(event.type, media);
            };
            for (const name of ['play', 'playing', 'pause', 'waiting', 'stalled', 'emptied', 'ended', 'error', 'timeupdate']) {
                media.addEventListener(name, onMediaEvent, true);
            }
        };

        const trackInitialMedia = () => {
            for (const media of document.querySelectorAll('video, audio')) ensureRecord(media);
        };

        const ensureRecord = media => {
            if (!(media instanceof HTMLMediaElement)) return null;
            let record = records.get(media);
            if (record) return record;
            if (tracked.size >= maxTracked) return null;
            const root = playerFor(media);
            const authorizedRoot = [...tracked].some(previous => {
                const previousRecord = records.get(previous);
                return previousRecord?.resumeIntent && previousRecord.playerRoot === root;
            });
            const inheritedPlayback = intentArmed && frameHadPlayback && root && root === playerRoot && authorizedRoot;
            record = {
                id: `m${nextID++}`,
                everPlayed: Boolean(inheritedPlayback),
                activeCandidate: false,
                resumeIntent: Boolean(inheritedPlayback),
                playerRoot: inheritedPlayback ? root : null,
                resumePending: false,
                lastTimeUpdate: 0
            };
            records.set(media, record);
            tracked.add(media);
            bindMedia(media, record);
            if (!media.paused && !media.ended) {
                record.everPlayed = true;
                record.activeCandidate = true;
                frameHadPlayback = true;
                record.playerRoot = root;
                playerRoot = root || playerRoot;
            }
            if (inheritedPlayback) send('replacement-tracked', media);
            return record;
        };

        // Capture media created after document start before site listeners handle play.
        document.addEventListener('play', event => {
            const record = ensureRecord(event.target);
            if (!record) return;
            record.everPlayed = true;
            record.activeCandidate = true;
            frameHadPlayback = true;
            playerRoot = playerFor(event.target) || playerRoot;
        }, true);
        document.addEventListener('playing', event => {
            const record = ensureRecord(event.target);
            if (!record) return;
            record.everPlayed = true;
            record.activeCandidate = true;
            frameHadPlayback = true;
            playerRoot = playerFor(event.target) || playerRoot;
        }, true);

        const arm = () => {
            if (userPausedDuringBackground) {
                send('native-arm-ignored-user-pause', null);
                return snapshot();
            }
            nativeBackgroundIntent = true;
            intentArmed = true;
            trackInitialMedia();
            for (const media of tracked) {
                const record = records.get(media);
                if (!record) continue;
                if (record.activeCandidate || (!media.paused && !media.ended)) {
                    record.everPlayed = true;
                    record.resumeIntent = true;
                }
            }
            send('native-arm', null, { trackedCount: tracked.size });
            scheduleRetries();
            scan();
            return snapshot();
        };

        const resumePending = async () => {
            send('native-resume', null, { trackedCount: tracked.size });
            scan();
            for (const media of [...tracked]) await resumeOne(media);
        };

        const activate = async () => {
            clearIntent('scene-active');
        };

        const snapshot = () => {
            trackInitialMedia();
            const media = [...tracked].map(element => {
                const record = records.get(element);
                const item = {
                    id: record?.id ?? null,
                    paused: Boolean(element.paused),
                    ended: Boolean(element.ended),
                    readyState: Number(element.readyState),
                    networkState: Number(element.networkState),
                    currentTime: Math.round(Number(element.currentTime || 0) * 10) / 10,
                    everPlayed: Boolean(record?.everPlayed),
                    activeCandidate: Boolean(record?.activeCandidate),
                    resumeIntent: Boolean(record?.resumeIntent)
                };
                send('media-snapshot', element, { activeCandidate: item.activeCandidate });
                return item;
            });
            const resumeIntentCount = media.filter(item => item.resumeIntent).length;
            send('snapshot', null, { trackedCount: tracked.size, resumeIntentCount, nativeBackgroundIntent, intentArmed });
            return {
                actualHidden: actualHidden(),
                actualVisibility: originalVisibility(),
                maskedVisibility: document.visibilityState,
                nativeBackgroundIntent,
                intentArmed,
                resumeIntentCount,
                media
            };
        };

        const visibilityListener = event => {
            const hidden = actualHidden();
            send(event.type, null, { eventHidden: hidden, eventVisibility: String(originalVisibility()).slice(0, 16) });
            if (hidden && !userPausedDuringBackground) {
                nativeBackgroundIntent = true;
                intentArmed = true;
                trackInitialMedia();
                for (const media of tracked) {
                    const record = records.get(media);
                    if (record?.activeCandidate || (!media.paused && !media.ended)) record.resumeIntent = true;
                }
                scheduleRetries();
            }
        };
        document.addEventListener('visibilitychange', visibilityListener, true);
        window.addEventListener('pagehide', visibilityListener, true);
        window.addEventListener('pageshow', visibilityListener, true);
        document.addEventListener('yt-navigate-start', () => {
            clearIntent('youtube-navigation');
            frameHadPlayback = false;
            playerRoot = null;
        }, true);
        window.addEventListener('beforeunload', () => clearIntent('document-unload'), true);

        if (window.HTMLMediaElement?.prototype) {
            const originalPause = HTMLMediaElement.prototype.pause;
            if (typeof originalPause === 'function') {
                HTMLMediaElement.prototype.pause = function(...args) {
                    const record = records.get(this);
                    const stack = cleanStack(new Error().stack);
                    send('pause-call', this, { stack: stack.join(' | '), suppressed: false });
                    if (record) {
                        record.activeCandidate = false;
                        record.resumeIntent = false;
                    }
                    return originalPause.apply(this, args);
                };
            }
        }

        const mediaSessionConstructor = window.MediaSession || Object.getPrototypeOf(navigator.mediaSession || {})?.constructor;
        if (mediaSessionConstructor?.prototype) {
            const originalSetActionHandler = mediaSessionConstructor.prototype.setActionHandler;
            if (typeof originalSetActionHandler === 'function') {
                mediaSessionConstructor.prototype.setActionHandler = function(action, handler) {
                    if (action !== 'pause' && action !== 'play') return originalSetActionHandler.call(this, action, handler);
                    send('media-session-handler', null, { action, removed: handler === null });
                    if (handler === null) return originalSetActionHandler.call(this, action, null);
                    const wrapped = function(event) {
                        send('media-session-action', null, { action });
                        if (action === 'pause') clearIntent('media-session-pause');
                        return handler.call(this, event);
                    };
                    return originalSetActionHandler.call(this, action, wrapped);
                };
            }
        }

        window.__oneFeedPlayback = { arm, resumePending, activate, clear: clearIntent, snapshot };
        trackInitialMedia();
        send('script-ready', null, { trackedCount: tracked.size });
    })();
    """#
}

@MainActor
private final class YouTubeMediaDiagnosticHandler: NSObject, WKScriptMessageHandler {
    private let allowedKeys: Set<String> = [
        "event", "mediaID", "paused", "ended", "readyState", "networkState", "currentTime",
        "errorCode", "everPlayed", "resumeIntent", "actualHidden", "actualVisibility",
        "maskedVisibility", "eventHidden", "eventVisibility", "trackedCount", "stack",
        "errorName", "reason", "action", "removed", "suppressed", "nativeBackgroundIntent",
        "intentArmed", "activeCandidate", "cause", "resumeIntentCount"
    ]
    private var minuteWindow = Date()
    private var messageCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if Date().timeIntervalSince(minuteWindow) >= 60 {
            minuteWindow = Date()
            messageCount = 0
        }
        guard messageCount < 240 else { return }
        messageCount += 1

        var safe: [String: Any] = [:]
        for (key, value) in body where allowedKeys.contains(key) {
            if let string = value as? String {
                safe[key] = String(string.prefix(key == "stack" ? 320 : 80))
            } else if value is NSNull {
                safe[key] = NSNull()
            } else if let number = value as? NSNumber {
                safe[key] = number
            }
        }
        guard JSONSerialization.isValidJSONObject(safe),
              let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              data.count <= 1800,
              let json = String(data: data, encoding: .utf8) else { return }
        NSLog("[OneFeed][YouTubeJS] %@", json)
    }
}
