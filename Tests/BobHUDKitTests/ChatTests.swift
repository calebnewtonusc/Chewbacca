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
        let blocks = Prose.blocks("One.\n\nTwo\nstill two.\n```\nlet x = 1\n```\nThree.")
        #expect(blocks == [
            .paragraph("One."), .paragraph("Two\nstill two."), .code("let x = 1"), .paragraph("Three."),
        ])
        #expect(Prose.blocks("").isEmpty)
        #expect(Prose.blocks("```\nopen fence") == [.code("open fence")])
    }
}
