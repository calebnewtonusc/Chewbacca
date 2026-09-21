import AppKit
import BobHUDKit
import os

/// The dictation bubble's behaviour: drag it, click it, speak, and the words go
/// into the box it is sitting on.
///
/// ## Why this is not the talk key
///
/// The talk key sends what you said to the assistant, which reads it and decides
/// what you meant. That is correct for a request and wrong for a sentence you
/// want typed into a message, and the two are indistinguishable from the audio.
/// On 2026-09-21, with Terminal in front, "create a bubble" came back as an
/// offer to draft a terminal prompt: the router did its job and the job was the
/// wrong one. The bubble removes the guess by making the person name the
/// destination with their hand before they open their mouth.
///
/// So nothing in this file goes near a model. A turn started from a bubble never
/// reaches `dispatch`, never reaches the router, and never reaches the pill. The
/// transcript goes into a text field and a notification of that goes up the
/// socket after the fact.
///
/// ## The gesture
///
/// Press, move, release. Under `Bubble.clickSlop` of travel it was a click;
/// over it, a drag that rebinds wherever it lands. Both halves are one pair of
/// monitors rather than a SwiftUI gesture, for the same reason the reticle is:
/// the glass only accepts the mouse where the window has been told something is
/// drawn, and a drag that leaves that rectangle would otherwise stop dead.
extension AppDelegate {
    static let bubbleLog = Logger(subsystem: "bob.hud", category: "bubble")

    /// How long a `live` turn may hear nothing before it closes itself.
    ///
    /// The person asked for click-to-start and click-again-to-stop, with
    /// silence as the backstop rather than the primary way out, so this is
    /// generous on purpose: 6 seconds. Short values were the failure mode of
    /// every silence timer in `VOICE-RESEARCH.md`, which cuts people off while
    /// they think. Guessed, never measured against this gesture.
    private static let dictationSilence: TimeInterval = 6

    /// How long the clean-up hop gets before the raw transcript is used.
    ///
    /// 1.5s. The bubble's whole promise is that the words land, so a model that
    /// is slow costs the punctuation and not the sentence.
    private static let cleanupBudget: TimeInterval = 1.5

    // MARK: Gesture

    func setUpBubbles() {
        // Global and local, in pairs. A global monitor sees only what other
        // applications get, and the glass goes solid the moment the pointer is
        // over a bubble, at which point the events come here instead. Missing
        // either one leaves a bubble that can be picked up and not put down.
        bubbleDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            Task { @MainActor in self?.bubblePress() }
        }
        localBubbleDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            Task { @MainActor in self?.bubblePress() }
            return event
        }
        bubbleDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] _ in
            Task { @MainActor in self?.bubbleDrag() }
        }
        localBubbleDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] event in
            Task { @MainActor in self?.bubbleDrag() }
            return event
        }
        bubbleUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] _ in
            Task { @MainActor in self?.bubbleRelease() }
        }
        localBubbleUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            Task { @MainActor in self?.bubbleRelease() }
            return event
        }
    }

    private func bubblePress() {
        guard !model.bubbles.isEmpty else { return }
        let point = Self.flipped(NSEvent.mouseLocation)
        guard let bubble = model.bubble(at: point) else { return }
        bubbleDragID = bubble.id
        bubbleDragFrom = point
        bubbleDragMoved = false
        bubbleDragOffset = CGSize(
            width: bubble.center.x - point.x, height: bubble.center.y - point.y)
    }

    private func bubbleDrag() {
        guard let id = bubbleDragID, let from = bubbleDragFrom else { return }
        let point = Self.flipped(NSEvent.mouseLocation)
        let travelled = hypot(point.x - from.x, point.y - from.y)
        if !bubbleDragMoved, travelled > Bubble.clickSlop {
            bubbleDragMoved = true
            // Picked up, so it is bound to nothing until it lands. A bubble
            // that kept its old field while being carried across the screen
            // would be a bubble that looks attached to whatever is under it and
            // types into something else.
            if model.bubbles.first(where: { $0.id == id })?.isBound == true {
                if dictating == id { endDictation(insert: false) }
                bubbleTargets.removeValue(forKey: id)
                bubbleAnchors.removeValue(forKey: id)
                model.setBubble(id, state: .unbound)
            }
        }
        guard bubbleDragMoved else { return }
        model.moveBubble(
            id,
            to: CGPoint(
                x: point.x + bubbleDragOffset.width, y: point.y + bubbleDragOffset.height))
        updateInteractive()
    }

    private func bubbleRelease() {
        guard let id = bubbleDragID else { return }
        let moved = bubbleDragMoved
        bubbleDragID = nil
        bubbleDragFrom = nil
        bubbleDragMoved = false
        guard let bubble = model.bubbles.first(where: { $0.id == id }) else { return }
        if moved {
            Task { await bind(id, at: bubble.center) }
        } else {
            Task { await click(bubble) }
        }
    }

    /// What a click means depends on what the bubble is.
    private func click(_ bubble: Bubble) async {
        switch bubble.state {
        case .unbound, .orphaned:
            // Parked without being dragged, or its field went away. Try where
            // it is: the person clicked it, so they mean it to work here.
            await bind(bubble.id, at: bubble.center, thenTalk: true)

        case .dimmed:
            // Bring the field forward rather than starting a turn. Dictating
            // into a window that is behind another one is how a sentence ends
            // up somewhere nobody saw.
            if let target = bubbleTargets[bubble.id] {
                NSRunningApplication(processIdentifier: target.appPid)?
                    .activate(options: [])
            }

        case .idle:
            await beginDictation(bubble.id)

        case .live:
            // Click again to stop, which is what the person chose over
            // hold-to-talk: the hand is on the trackpad, not on a key, and a
            // gesture that needs holding cannot be used while typing.
            endDictation(insert: true)

        case .thinking:
            break
        }
    }

    // MARK: Binding

    /// Work out what is under the bubble and hold on to it.
    private func bind(_ id: String, at point: CGPoint, thenTalk: Bool = false) async {
        guard TextTarget.trusted else {
            await refuseUntrusted(id)
            return
        }
        await bound(id, TextTarget.bind(at: point), thenTalk: thenTalk)
    }

    /// Accessibility has not been granted.
    private func refuseUntrusted(_ id: String) async {
        // The one thing here a person has to do by hand. The display already
        // holds Input Monitoring for the talk key; Accessibility is a separate
        // switch and the bubble is the first thing that needs it.
        model.setBubble(
            id, state: .unbound, note: TextTarget.BindFailure.notTrusted.reason)
        model.onEvent?(
            .bubble(
                id: id, state: .unbound, app: nil,
                note: TextTarget.BindFailure.notTrusted.reason))
        TextTarget.requestTrust()
    }

    private func bound(
        _ id: String, _ result: Result<TextTarget, TextTarget.BindFailure>, thenTalk: Bool
    ) async {
        switch result {
        case .success(let target):
            bubbleTargets[id] = target
            // Reset on every drop: the offset is from where they just put it.
            bubbleAnchors.removeValue(forKey: id)
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let state: BubbleState = front == target.appPid ? .idle : .dimmed
            model.setBubble(id, state: state, app: target.appName)
            model.onEvent?(
                .bubble(id: id, state: state, app: target.appName, note: nil))
            startFollowing()
            if thenTalk, state == .idle { await beginDictation(id) }

        case .failure(let why):
            bubbleTargets.removeValue(forKey: id)
            bubbleAnchors.removeValue(forKey: id)
            // Stays where it was dropped, saying why, rather than springing
            // back to the pill. The person aimed at something; the answer is
            // that it was the wrong thing, and moving the bubble would hide
            // which thing they aimed at.
            model.setBubble(id, state: .unbound, note: why.reason)
            model.onEvent?(.bubble(id: id, state: .unbound, app: nil, note: why.reason))
            if why == .notTrusted { TextTarget.requestTrust() }
        }
    }

    /// Follow every bound field, so a bubble stays on the box when its window
    /// is dragged or scrolled.
    ///
    /// One task for all of them, at `Bubble.poll`. It stops itself the moment
    /// nothing is bound: a timer running forever against no work is how a HUD
    /// ends up costing battery while it draws nothing.
    private func startFollowing() {
        guard bubbleFollow == nil else { return }
        bubbleFollow = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.bubbleTargets.isEmpty else { break }
                for (id, target) in self.bubbleTargets {
                    // A bubble being carried by hand is not following anything.
                    if self.bubbleDragID == id { continue }
                    guard let look = await target.look() else {
                        self.orphan(id)
                        continue
                    }
                    guard let bubble = self.model.bubbles.first(where: { $0.id == id })
                    else {
                        self.bubbleTargets.removeValue(forKey: id)
                        self.bubbleAnchors.removeValue(forKey: id)
                        continue
                    }
                    // It stays exactly where it was dropped, and moves by
                    // however far the field has moved. Not pinned to the
                    // field's own trailing edge, which is what this did first
                    // and what the probe on 2026-09-21 disproved: Terminal's
                    // `AXTextArea` reported 230,-255 2117x1631 for a window
                    // 1100 points tall, because the frame covers the whole
                    // scrollback rather than the visible box. Pinning to that
                    // edge threw the bubble hundreds of points from where the
                    // person put it, and off the top of the screen in a long
                    // buffer. A delta cannot do that: it is zero while the
                    // window is still.
                    guard let anchor = self.bubbleAnchors[id] else {
                        self.bubbleAnchors[id] = Anchor(
                            field: look.frame.origin, bubble: bubble.center)
                        continue
                    }
                    let centre = CGPoint(
                        x: anchor.bubble.x + (look.frame.minX - anchor.field.x),
                        y: anchor.bubble.y + (look.frame.minY - anchor.field.y))
                    if abs(centre.x - bubble.center.x) > 0.5
                        || abs(centre.y - bubble.center.y) > 0.5 {
                        self.model.moveBubble(id, to: Self.onScreen(centre))
                        self.updateInteractive()
                    }
                    // Frontmost or not, which is the difference between `idle`
                    // and `dimmed`. Never touched while a turn is open: the
                    // microphone is already pointed at this field.
                    if bubble.state == .idle || bubble.state == .dimmed {
                        let front = NSWorkspace.shared.frontmostApplication?
                            .processIdentifier
                        let next: BubbleState = front == look.pid ? .idle : .dimmed
                        if next != bubble.state { self.model.setBubble(id, state: next) }
                    }
                }
                try? await Task.sleep(for: .seconds(Bubble.poll))
            }
            self?.bubbleFollow = nil
        }
    }

    /// The field is gone. Say so and stop following it.
    ///
    /// Deliberately does not hunt for a replacement. A bubble that rebinds to
    /// whatever is now under it is a bubble that puts your words in a stranger's
    /// window, and the person is one drag away from fixing it themselves.
    private func orphan(_ id: String) {
        bubbleTargets.removeValue(forKey: id)
        bubbleAnchors.removeValue(forKey: id)
        if dictating == id { endDictation(insert: false) }
        model.setBubble(id, state: .orphaned, note: "the field is gone")
        model.onEvent?(
            .bubble(id: id, state: .orphaned, app: nil, note: "the field is gone"))
    }

    // MARK: The turn

    private func beginDictation(_ id: String) async {
        guard dictating == nil else { return }
        guard let target = bubbleTargets[id] else { return }
        // Dictation rides on push-to-talk's own path, so it needs that mode.
        // `beginPush` returns silently in any other, which left the bubble
        // sitting in `live` with the microphone shut and nothing to close it:
        // the one failure a listening indicator must never have.
        guard voice.mode == .pushToTalk else {
            let why = voice.mode == .off
                ? "listening is off, turn it on in the menu"
                : "dictation needs push to talk, not the wake word"
            model.setBubble(id, state: .idle, note: why)
            model.onEvent?(
                .bubble(id: id, state: .idle, app: target.appName, note: why))
            return
        }
        // The bubble took the click, so the field underneath never got one and
        // may have no caret. This is where the words are about to go, so it is
        // worth putting the caret there before the microphone opens rather than
        // after, when there is text waiting.
        await target.focus()
        dictating = id
        model.setBubble(id, state: .live)
        model.onEvent?(.bubble(id: id, state: .live, app: target.appName, note: nil))
        Self.bubbleLog.notice("bubble.turn open id=\(id, privacy: .public)")
        voice.beginPush()
        armQuiet()
    }

    /// Close the turn. `insert` false throws the words away, which is what a
    /// cancel and a field that went away both need.
    private func endDictation(insert: Bool) {
        guard let id = dictating else { return }
        dictationQuiet?.cancel()
        dictationQuiet = nil
        if insert {
            model.setBubble(id, state: .thinking)
            voice.endPush()
            armStall(id)
        } else {
            dictating = nil
            voice.cancelPush()
            let state: BubbleState = bubbleTargets[id] == nil ? .orphaned : .idle
            model.setBubble(id, state: state)
        }
    }

    /// A turn that closed and produced nothing at all.
    ///
    /// `endPush` declines when the microphone was never open, which happens
    /// when the two permission hops had not finished by the time the person
    /// clicked. Nothing is emitted in that case, so without this the bubble
    /// spins in `thinking` for ever and the only way out is taking it down.
    /// Three seconds: `VoiceListener.finalFloor` is three, so anything the
    /// recogniser was going to say has been said by then.
    private func armStall(_ id: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self,
                  self.model.bubbles.first(where: { $0.id == id })?.state == .thinking,
                  self.pendingInsert[id] == nil
            else { return }
            Self.bubbleLog.notice("bubble.turn stalled id=\(id, privacy: .public)")
            self.model.setBubble(
                id, state: self.bubbleTargets[id] == nil ? .orphaned : .idle,
                note: "nothing was heard")
        }
    }

    /// Nobody is talking. Close the turn and keep whatever was heard.
    private func armQuiet() {
        dictationQuiet?.cancel()
        dictationQuiet = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.dictationSilence))
            guard !Task.isCancelled, let self, self.dictating != nil else { return }
            Self.bubbleLog.notice("bubble.turn quiet")
            self.endDictation(insert: true)
        }
    }

    /// A voice signal while a bubble owns the turn. True means it was consumed
    /// and the assistant's own handling must not also run.
    ///
    /// Returning a Bool rather than splitting `VoiceListener` in two is
    /// deliberate. The listener has one microphone, one recogniser and one turn
    /// counter, and every bug in `VOICE-RESEARCH.md` came from something with
    /// memory being wired to that signal. Adding a mode would have put a second
    /// state machine inside the class that already holds the fragile one; this
    /// puts the fork outside it, where push-to-talk cannot be reached by
    /// anything the bubble does.
    func dictationSignal(_ signal: VoiceListener.Signal) -> Bool {
        guard let id = dictating else { return false }
        switch signal {
        case .partial(let text):
            model.setBubbleHeard(id, text)
            // Every revision is a sign of life, so the quiet timer restarts.
            armQuiet()
            return true

        case .heard(let text):
            dictating = nil
            dictationQuiet?.cancel()
            dictationQuiet = nil
            heard(text, on: id)
            return true

        case .failed(let message):
            dictating = nil
            dictationQuiet?.cancel()
            dictationQuiet = nil
            // On the bubble, not on the pill. The person is looking at the box
            // they were dictating into, which may be on the other side of the
            // screen from the pill.
            let state: BubbleState = bubbleTargets[id] == nil ? .orphaned : .idle
            model.setBubble(id, state: state, note: message)
            Self.bubbleLog.notice("bubble.turn failed reason=\(message, privacy: .public)")
            return true

        case .level(let level):
            // The bubble's ring breathes on its own clock rather than on the
            // input level, so the level is swallowed here to keep the presence
            // band out of a turn that is not the assistant's.
            _ = level
            return true

        case .listening:
            return true
        }
    }

    // MARK: Insertion

    /// The turn closed. Ask the bridge to tidy the sentence, and insert it
    /// anyway if the answer is slow.
    ///
    /// The race is settled by a token rather than by whoever arrives first,
    /// which is the pattern `VoiceListener.turn` already uses in this codebase
    /// and for the same reason: two paths can both reach the insert, the field
    /// takes both, and a sentence typed twice is worse than a sentence typed
    /// without a comma. The token makes the loser inert.
    private func heard(_ raw: String, on id: String) {
        let fallback = Bubble.punctuate(raw)
        insertToken += 1
        let token = insertToken
        pendingInsert[id] = Pending(token: token, text: fallback)
        model.setBubble(id, state: .thinking)
        model.onEvent?(.clean(id: id, text: raw))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.cleanupBudget))
            guard let self, let pending = self.pendingInsert[id], pending.token == token
            else { return }
            Self.bubbleLog.notice("bubble.clean timeout id=\(id, privacy: .public)")
            await self.commit(pending.text, into: id, token: token)
        }
    }

    /// The tidied sentence came back. Whoever is still holding the token wins.
    func cleaned(_ id: String, _ text: String) {
        guard let pending = pendingInsert[id] else { return }
        // An empty answer is a bridge that had nothing to add, not an
        // instruction to insert nothing.
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await commit(next.isEmpty ? pending.text : next, into: id, token: pending.token) }
    }

    /// Nobody was listening on the socket, so there is nothing to wait for.
    func nobodyToClean(_ id: String) {
        guard let pending = pendingInsert[id] else { return }
        Task { await commit(pending.text, into: id, token: pending.token) }
    }

    /// Put the words in the field, then say so.
    private func commit(_ raw: String, into id: String, token: Int) async {
        guard pendingInsert[id]?.token == token else { return }
        pendingInsert.removeValue(forKey: id)
        let text = Bubble.punctuate(raw)
        guard !text.isEmpty else {
            model.setBubble(id, state: bubbleTargets[id] == nil ? .orphaned : .idle)
            return
        }
        guard let target = bubbleTargets[id] else {
            orphan(id)
            return
        }
        var wrote = await target.insert(text)
        if !wrote { wrote = await Self.paste(text, pid: target.appPid) }

        if wrote {
            model.setBubble(id, state: .idle, app: target.appName)
            model.onEvent?(.dictated(id: id, text: text))
            Self.bubbleLog.notice("bubble.said chars=\(text.count)")
        } else {
            // The clipboard still holds it, so nothing spoken is lost even
            // though nothing was typed. Saying which is the difference between
            // a bug and one keystroke.
            model.setBubble(id, state: .idle, note: "in the clipboard, paste it")
            model.onEvent?(
                .bubble(
                    id: id, state: .idle, app: target.appName,
                    note: "in the clipboard, paste it"))
        }
    }

    /// Tier two: the clipboard and a paste, through peekaboo.
    ///
    /// Runs only when the field refused `kAXSelectedText`, which is every
    /// Electron application and some web views. It costs the person's clipboard
    /// and it is the reason the previous contents are put back afterwards.
    ///
    /// `peekaboo` rather than a synthesised Command-V from here, because it
    /// already holds the permission for posting events and has the retry
    /// behaviour for an application that is slow to take focus. If it is not
    /// installed this returns false and the words stay on the clipboard, which
    /// is the honest failure: the person pastes them.
    private static func paste(_ text: String, pid: pid_t) async -> Bool {
        let board = NSPasteboard.general
        let previous = board.string(forType: .string)
        board.clearContents()
        board.setString(text, forType: .string)

        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        let ok = await run("/usr/bin/env", ["peekaboo", "hotkey", "cmd,v"])
        bubbleLog.notice("bubble.insert tier=paste ok=\(ok)")

        // Put the clipboard back, after the paste has had time to read it. A
        // clipboard that silently becomes whatever you last dictated is a
        // worse bug than a failed insert, because it surfaces an hour later in
        // a different window.
        if ok {
            try? await Task.sleep(for: .milliseconds(350))
            board.clearContents()
            if let previous { board.setString(previous, forType: .string) }
        }
        return ok
    }

    private static func run(_ path: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { done in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
            do { try task.run() } catch { done.resume(returning: false) }
        }
    }

    /// Keep a followed bubble reachable.
    ///
    /// A window dragged most of the way off the screen takes its bubble with
    /// it, which is correct until the bubble is the part that has gone: a
    /// bubble at -40 is a bubble that cannot be clicked or moved, and the only
    /// way back is `hud-bubble clear`. So it stops at the edge of the glass,
    /// still bound, still following, and comes back off the edge when the
    /// window does.
    private static func onScreen(_ centre: CGPoint) -> CGPoint {
        guard let screen = OverlayWindow.active else { return centre }
        let inset = Bubble.size / 2
        return CGPoint(
            x: min(max(centre.x, inset), screen.frame.width - inset),
            y: min(max(centre.y, inset), screen.frame.height - inset))
    }

    // MARK: Asked for by name

    /// Spawn one, from the socket or the menu. Returns its id.
    @discardableResult
    func spawnBubble() -> String {
        let bubble = model.spawnBubble()
        overlay?.show()
        updateInteractive()
        model.onEvent?(
            .bubble(id: bubble.id, state: .unbound, app: nil, note: nil))
        Self.bubbleLog.notice("bubble.spawn id=\(bubble.id, privacy: .public)")
        return bubble.id
    }

    /// Take them all down.
    func clearBubbles() {
        if dictating != nil { endDictation(insert: false) }
        bubbleTargets.removeAll()
        bubbleAnchors.removeAll()
        bubbleFollow?.cancel()
        bubbleFollow = nil
        for bubble in model.bubbles { model.removeBubble(bubble.id) }
        updateInteractive()
    }
}
