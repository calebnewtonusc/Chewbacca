import AppKit
import Testing

@testable import BobHUDKit

/// The conversation behind the panel: what goes in when, and what closes it.
@Suite("Conversation")
@MainActor
struct ChatTests {
    @Test("a request opens a turn and an empty answer after it")
    func askedOpensAnAnswer() {
        let model = OverlayModel()
        model.asked("what is due this week", typed: false)
        #expect(model.turns.count == 2)
        #expect(model.turns[0].role == .person && model.turns[0].text == "what is due this week")
        #expect(model.turns[1].role == .assistant && model.turns[1].text.isEmpty && !model.turns[1].done)
    }

    @Test("the long-answer switch ships on, is kept, and is told to the bridge")
    func longAnswerSwitch() {
        UserDefaults.standard.removeObject(forKey: OverlayModel.longAnswersKey)
        defer { UserDefaults.standard.removeObject(forKey: OverlayModel.longAnswersKey) }
        let model = OverlayModel()
        #expect(model.longAnswersWritten)
        #expect(model.preferenceEvent.line == "e prefer voice long=written")

        var sent: [String] = []
        model.onEvent = { sent.append($0.line) }
        model.setLongAnswersWritten(false)
        #expect(!model.longAnswersWritten)
        #expect(sent == ["e prefer voice long=spoken"])
        #expect(!OverlayModel().longAnswersWritten, "the switch is not kept across launches")
    }

    @Test("the written answer replaces itself until done")
    func writeReplaces() {
        let model = OverlayModel()
        model.asked("capital of France", typed: true)
        model.apply(.write(text: "Paris.", done: false))
        model.apply(.write(text: "Paris.\n\nIt has been since 987.", done: true))
        #expect(model.turns.count == 2)
        #expect(model.turns[1].text == "Paris.\n\nIt has been since 987.")
        #expect(model.turns[1].done)
        #expect(model.turns[1].typed)
    }

    @Test("done closes an answer nobody wrote, with the pill's line")
    func doneSettlesWithThePill() {
        // A one-sentence reply from a bridge that only ever said it.
        let model = OverlayModel()
        model.asked("is Friday free", typed: false)
        model.setPresence(.thinking, amplitude: 0)
        model.say("Friday 3pm is free.")
        model.setPresence(.done, amplitude: 0)
        #expect(model.turns[1].done)
        #expect(model.turns[1].text == "Friday 3pm is free.")
    }

    @Test("a failure closes the answer with what went wrong")
    func failureSettles() {
        let model = OverlayModel()
        model.asked("text Sagar", typed: false)
        model.setPresence(.failed, amplitude: 0)
        model.fail("Nothing is listening. Run: hud listen", hold: 1)
        #expect(model.turns[1].done)
        #expect(model.turns[1].text == "Nothing is listening. Run: hud listen")
    }

    @Test("a stop closes the answer with the words the pill shows")
    func stopSettles() {
        let model = OverlayModel()
        model.asked("plan my week", typed: false)
        model.setPresence(.thinking, amplitude: 0)
        model.cancelRun()
        #expect(model.turns[1].done)
        #expect(model.turns[1].text == "Stopped.")
    }

    @Test("a write with nothing open opens an answer")
    func writeAlone() {
        let model = OverlayModel()
        model.apply(.write(text: "From a script.", done: true))
        #expect(model.turns.count == 1)
        #expect(model.turns[0].role == .assistant && model.turns[0].done)
    }

    @Test("opening and closing the panel calls out, once each")
    func openClose() {
        let model = OverlayModel()
        var opened = 0
        var closed = 0
        model.onChatOpen = { opened += 1 }
        model.onChatClose = { closed += 1 }
        model.openChat()
        model.openChat()
        #expect(model.chatOpen && opened == 1)
        model.toggleChat()
        model.closeChat()
        #expect(!model.chatOpen && closed == 1)
    }

    @Test("Escape keeps the conversation and closes the panel; clear forgets it")
    func resetKeepsTurns() {
        let model = OverlayModel()
        model.asked("hello", typed: true)
        model.apply(.write(text: "Hi.", done: true))
        model.openChat()
        model.reset()
        #expect(!model.chatOpen)
        #expect(model.turns.count == 2)
        model.clearChat()
        #expect(model.turns.isEmpty)
    }

    @Test("the conversation is capped")
    func capped() {
        let model = OverlayModel()
        for i in 0..<(OverlayModel.maxTurns) {
            model.asked("q\(i)", typed: true)
        }
        #expect(model.turns.count == OverlayModel.maxTurns)
        #expect(model.turns.last?.role == .assistant)
    }

    @Test("prose splits into paragraphs and fenced code")
    func proseBlocks() {
        let blocks = Prose.blocks("One.\n\nTwo\nstill two.\n```swift\nlet x = 1\n```\nThree.")
        #expect(blocks == [
            .paragraph("One."), .paragraph("Two\nstill two."),
            .code(language: "swift", text: "let x = 1"), .paragraph("Three."),
        ])
        #expect(Prose.blocks("").isEmpty)
        #expect(Prose.blocks("```\nopen fence") == [.code(language: "", text: "open fence")])
    }

    @Test("prose draws headings, lists, quotes, rules and tables as their own blocks")
    func proseStructure() {
        let text = """
        ## Today

        - one
        - two
        wraps
        1. first
        2) second
        > a quote
        ---
        | a | b |
        |---|---|
        | 1 | 2 |
        plain again
        """
        #expect(Prose.blocks(text) == [
            .heading(level: 2, text: "Today"),
            .bullets(["one", "two wraps"]),
            .numbered(["first", "second"]),
            .quote("a quote"),
            .rule,
            .table(header: ["a", "b"], rows: [["1", "2"]]),
            .paragraph("plain again"),
        ])
        // A number in prose is not a list, and a lone dash is not a rule.
        #expect(Prose.blocks("2024 was long.\n-") == [.paragraph("2024 was long.\n-")])
    }

    @Test("a step lands on the open answer and on the pill, and is not repeated")
    func steps() {
        let model = OverlayModel()
        model.asked("what is due", typed: true)
        model.apply(.step("Reading the ledger"))
        model.apply(.step("Reading the ledger"))
        model.apply(.step("Checking the calendar"))
        #expect(model.turns.last?.steps == ["Reading the ledger", "Checking the calendar"])
        #expect(model.pill.saying == "Checking the calendar")
        #expect(model.pill.step)
        model.apply(.say("Two things are due."))
        #expect(!model.pill.step)
        model.apply(.write(text: "Two things are due.", done: true))
        #expect(model.turns.last?.endedAt != nil)
        // A step with no answer open is just a line on the pill.
        model.apply(.step("Late step"))
        #expect(model.turns.last?.steps.count == 2)
    }

    @Test("the panel keeps a frame only on the main display")
    func placing() {
        let main = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let onMain = NSRect(x: 1000, y: 300, width: 520, height: 600)
        // The laptop screen below the monitor, where a frame was saved while
        // the glass still followed the pointer.
        let below = NSRect(x: 1034, y: -951, width: 520, height: 600)
        #expect(ChatWindow.needsPlacing(frame: below, on: main, restored: true, placed: false))
        #expect(ChatWindow.needsPlacing(frame: below, on: main, restored: true, placed: true))
        #expect(!ChatWindow.needsPlacing(frame: onMain, on: main, restored: true, placed: false))
        // No saved frame: at the pill the first time, then where it was dragged.
        #expect(ChatWindow.needsPlacing(frame: onMain, on: main, restored: false, placed: false))
        #expect(!ChatWindow.needsPlacing(frame: onMain, on: main, restored: false, placed: true))
    }

    @Test("opening counts, so the panel can animate each entrance")
    func openings() {
        let model = OverlayModel()
        model.openChat()
        model.openChat()
        model.closeChat()
        model.openChat()
        #expect(model.chatOpenings == 2)
    }
}
