import Foundation

/// Routes a dictation that starts with "Chewbacca" or "Chewie" to Claude Code
/// instead of pasting it.
///
/// What comes back is SHOWN and copied, never typed. An answer to a question is
/// not dictated text, and synthesising Cmd-V for it drops it into whatever
/// happened to have focus.
///
/// The point is that dictation and conversation are the same gesture. Holding
/// fn and saying "Chewie, make a note with all the texts I need to answer" runs
/// a real agent with real tools against the machine, and what lands in the field
/// is the answer rather than the sentence.
///
/// Everything else still pastes exactly as before. This only fires on the wake
/// word, because an agent round trip costs twenty seconds and nobody wants that
/// on an ordinary sentence.
public enum ChewieRouter {

    // MARK: - Wake word

    /// Words that hand the transcript to Claude. Speech recognisers hear the
    /// name several ways, and a wake word that only works when the recogniser
    /// spells it correctly is a wake word that does not work.
    private static let wakeWords = [
        "chewbacca", "chewie", "chewy", "chubaka", "chewbaca", "chubacca",
    ]

    /// Returns the prompt with the wake word removed, or nil when this is an
    /// ordinary dictation that should paste.
    public static func prompt(from transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        for word in wakeWords {
            guard lower.hasPrefix(word) else { continue }
            // The wake word has to END there. Without this check "Chewy's bowl
            // is empty" matches the prefix, the apostrophe survives the trim,
            // and a sentence about a dog goes to an agent instead of the page.
            let after = lower.dropFirst(word.count).first
            if let after, !" ,.:;!?-\u{2014}\n\t".contains(after) { continue }
            var rest = String(trimmed.dropFirst(word.count))
            // "Chewie, make a note" and "Chewbacca: do the thing" both leave
            // punctuation behind that is addressed to the assistant, not part
            // of the request.
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?-\u{2014}\n\t"))
            // A bare "Chewie" with nothing after it is someone testing the mic,
            // not a request. Pasting it is the right answer.
            guard rest.count >= 2 else { return nil }
            return rest
        }
        return nil
    }

    // MARK: - Running the agent

    /// What comes back lands at a cursor, in whatever the user was typing in.
    /// A chat-shaped reply is wrong there: no preamble, no restating the
    /// request, no offer of next steps. Say what happened, or give the answer,
    /// and stop.
    static let voiceStyle = """
        You are Chewie, reached by voice through a dictation key. Act, do not \
        deliberate. The user is holding a key waiting.

        REACH FOR THE LOCAL CLI FIRST. These read and write the user's own \
        machine, and they are almost always the right answer:

        - `people` for anyone in their life: `people show <name>`, \
          `people note <name> "..." --dim <dimension>`, `people log <name>`, \
          `people task add <name> "..." --due <date>`, `people reconnect`, \
          `people today`, `people texts --days 3`, `people texts --who <name>`, \
          `people texts search "..."`, `people stats`. This is a local SQLite \
          file. It is NOT Medha, NOT Amber, and NOT any MCP server: do not \
          reach for those for a question about the user's own contacts.
        - `coursework due`, `coursework today`, `coursework policy <course> ai` \
          for anything about classes. Never state a deadline you did not read.
        - `mac` for Calendar, Reminders, Contacts, Mail, Messages, Notes.
        - The second brain at ~/second-brain for durable facts about their life.

        WHEN THEY ARE JUST TALKING ABOUT THEIR LIFE, WRITE IT DOWN. A voice note \
        about a person becomes `people note`. Something they promised somebody \
        becomes `people task add`. A durable fact about themselves goes to \
        ~/second-brain. Do it in the same turn, then say in one line what you \
        recorded and where. Do not ask whether they want it saved.

        WHEN THEY ASK FOR SOMETHING DONE ON THE COMPUTER, DO IT. You have the \
        tools. Do not describe how they could do it themselves.

        Never invent a fact about a person, a number, or a date. If a lookup \
        fails, say the lookup failed. A confidently wrong answer here is worse \
        than no answer, because it is read at a glance and believed.

        The reply is SHOWN to the user on a small on-screen pill and copied \
        to their clipboard. It is not typed into anything. So:

        - Answer in one or two sentences. Three is already too many.
        - No preamble, no session opener, no prayer, no restating the question, \
          no offer of further help. Start with the answer.
        - If you performed an action, say what you did in one short line, past \
          tense, with the specific thing named. "Noted 4 unanswered texts: \
          Sagar, Maggie, Declan, Emma." Not "I have created a note for you."
        - No markdown headers, no bullet lists unless the answer genuinely is a \
          list, and then keep it under five short items.
        - If you could not do it, say so in one line and name what blocked you.

        The user is holding a key waiting for this. Brevity is the whole job.
        """

    /// Whether the on-device model can answer this without tools.
    ///
    /// Qwen3-4B is already loaded and warm, so it replies in about a second
    /// against Claude Code's twenty. But it has no shell, no files and no
    /// agent loop, so the moment a request touches the user's own data or asks
    /// for something to happen on the machine, a local answer is not a slower
    /// answer, it is an invented one.
    ///
    /// So this is deliberately mean. Anything with a first person pronoun, an
    /// action verb, or a noun naming the user's data goes to Claude. What is
    /// left is greetings and general knowledge, which is exactly the set that
    /// was costing twenty seconds to say hello.
    public static func isLocallyAnswerable(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let words = lower.split { !$0.isLetter && $0 != "'" }
        guard words.count <= 14 else { return false }

        // Anything about the user's own world needs the real tools.
        let personal: Set<Substring> = [
            "my", "mine", "me", "i", "i'm", "i've", "our", "we",
        ]
        if words.contains(where: personal.contains) { return false }

        let actions: Set<Substring> = [
            "send", "open", "make", "add", "note", "remind", "text", "email",
            "schedule", "delete", "run", "find", "search", "log", "write",
            "create", "call", "message", "draft", "close", "launch", "play",
            "set", "update", "check", "read", "show", "list", "fix", "push",
            // Talking ABOUT someone is a lookup, not general knowledge.
            "say", "said", "says", "tell", "told", "talk", "talked", "mention",
            "mentioned", "ask", "asked", "reply", "replied", "answer",
        ]
        if words.contains(where: actions.contains) { return false }

        let data: Set<Substring> = [
            "texts", "messages", "calendar", "notes", "task", "tasks", "contact",
            "contacts", "email", "emails", "file", "files", "deadline",
            "deadlines", "class", "classes", "homework", "reminder", "reminders",
            "inbox", "meeting", "meetings", "everyone", "anyone", "somebody",
            // Time words almost always mean "of mine": what is due this week.
            "due", "today", "tomorrow", "tonight", "yesterday", "week",
            "weekend", "birthday", "birthdays",
        ]
        if words.contains(where: data.contains) { return false }

        // A proper noun that is not the first word is almost always a person or
        // a company, and a question about one of those needs a real lookup.
        // "What is the capital of France" survives because France is a place in
        // general knowledge; the cost of being wrong the other way is inventing
        // a fact about somebody the user actually knows, so this errs strict.
        let original = prompt.split { !$0.isLetter }
        if original.dropFirst().contains(where: { $0.first?.isUppercase == true }) {
            return false
        }

        return true
    }

    /// What the on-device model gets when Claude could not run.
    ///
    /// It has no tools, no CLIs and no filesystem, so the honest thing is to
    /// tell it that and let it say it cannot rather than invent a contact, a
    /// deadline, or a number. A wrong answer here is worse than no answer,
    /// because it arrives looking exactly like a real one.
    public static func localFallbackPrompt(_ prompt: String) -> String {
        """
        You are a small on-device model standing in for an agent that could not \
        be reached. You have NO tools: no shell, no files, no contacts, no \
        calendar, no notes, no internet.

        Answer in one or two sentences if the request is something you can \
        genuinely answer from general knowledge alone.

        If it needs the user's own data or an action on their computer, say so \
        in one short line and stop. For example: "Can't reach Claude, and I \
        can't read your contacts from here." Never guess a name, a number, a \
        date, or a file. Never claim you did something.

        The request:

        \(prompt)
        """
    }

    public enum ChewieError: LocalizedError {
        case notInstalled
        case timedOut(seconds: Int)
        case failed(String)
        case noFullDiskAccess

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Claude Code is not installed, so Chewie has nothing to ask."
            case .timedOut(let s):
                return "Chewie took longer than \(s)s and was stopped."
            case .failed(let m):
                return m
            case .noFullDiskAccess:
                return "Give Plynn Full Disk Access, then Chewie can read your data."
            }
        }
    }

    /// The app is launched by Finder, which gives it a short PATH that has no
    /// nvm, no Homebrew and therefore no `claude`. Resolving it by hand is the
    /// difference between this working and failing with "not installed" on a
    /// machine where it is plainly installed.
    static func claudeExecutable() -> String? {
        let fm = FileManager.default
        var candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.local/bin/claude",
            NSHomeDirectory() + "/.claude/local/claude",
        ]
        // Any nvm-managed node install, newest first.
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            for v in versions.sorted(by: >) { candidates.append("\(nvm)/\(v)/bin/claude") }
        }
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        // Last resort: ask a login shell, which sources the user's profile.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return nil }
        probe.waitUntilExit()
        let out = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fm.isExecutableFile(atPath: out) ? out : nil
    }

    /// Ask Claude Code, with the user's own instructions, skills and tools.
    ///
    /// Runs in the home directory on purpose: that is where CLAUDE.md, the
    /// skills and the CLIs live, so "make a note" reaches the same tools it
    /// would in a terminal session.
    /// Selected text travels with the request. "Chewie, make this shorter" is
    /// meaningless without the thing being pointed at.
    public static func compose(prompt: String, selection: String?) -> String {
        guard let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return prompt }
        return """
            \(prompt)

            The user had this text selected when they asked. It is what "this", \
            "that" and "it" refer to:

            \(selection)
            """
    }

    /// Whether this process can read the files behind the user's own data.
    ///
    /// A subprocess is attributed to the app that launched it, so Chewie
    /// inherits Plynn's privacy grants rather than the terminal's. Without Full
    /// Disk Access every question about texts, mail or notes fails from Plynn
    /// while the identical command works in a terminal, and the failure looks
    /// like the agent being stupid rather than the app being fenced in.
    public static func hasFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Messages/chat.db"
        guard FileManager.default.fileExists(atPath: probe) else { return true }
        return FileManager.default.isReadableFile(atPath: probe)
    }

    public static func ask(_ prompt: String, timeout: Int = 180) async throws -> String {
        guard let exe = claudeExecutable() else { throw ChewieError.notInstalled }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        // --strict-mcp-config loads no MCP servers. That cuts the work by about
        // four times, and it also stops the agent wandering: asked how many
        // people were in the local store, a build with the servers loaded
        // reached for a remote CRM and invented an answer about somebody else's
        // contacts. The local CLIs named in voiceStyle are what this needs.
        //
        // Sonnet, not Haiku. The answer no longer blocks a paste, so the user
        // is not holding a key waiting to type, and the requests that matter
        // here chain several CLI calls together, which is exactly where Haiku
        // got lost. About twenty seconds of the round trip is Claude Code
        // starting up and cannot be removed from here anyway. Override with
        // `defaults write co.charmtechnologies.plynn.spike chewieModel haiku`.
        let model = UserDefaults.standard.string(forKey: "chewieModel") ?? "sonnet"
        proc.arguments = [
            "-p", "--output-format", "json",
            "--strict-mcp-config",
            "--model", model,
            "--append-system-prompt", voiceStyle,
            prompt,
        ]
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] =
            "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + (env["PATH"] ?? "")
        proc.environment = env

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice

        try proc.run()

        // Drain on a background queue, because a prompt that produces more
        // output than the pipe buffer holds deadlocks if nobody reads it.
        //
        // The read has to RACE the deadline rather than precede it.
        // readDataToEndOfFile returns only when the child closes stdout, so
        // awaiting it first meant the timeout loop did not start until the
        // process had already finished: a genuinely hung `claude` blocked here
        // forever and the timeout was unreachable in the one case it existed
        // for. Kill on the deadline, and the blocked read then returns on EOF.
        let reader = Task.detached(priority: .userInitiated) { () -> Data in
            out.fileHandleForReading.readDataToEndOfFile()
        }
        let watchdog = Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(TimeInterval(timeout))
            while Date() < deadline {
                if Task.isCancelled { return }
                if !proc.isRunning { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if proc.isRunning { proc.terminate() }
        }
        let data = await reader.value
        proc.waitUntilExit()
        watchdog.cancel()
        // terminate() is SIGTERM, so a process the watchdog killed is the one
        // that died to a signal. Anything else exited on its own terms.
        if proc.terminationReason == .uncaughtSignal {
            throw ChewieError.timedOut(seconds: timeout)
        }

        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw ChewieError.failed(
                raw.isEmpty ? "Chewie returned nothing." : String(raw.prefix(300)))
        }
        if let isError = obj["is_error"] as? Bool, isError {
            throw ChewieError.failed((obj["result"] as? String) ?? "Chewie failed.")
        }
        guard let result = obj["result"] as? String else {
            throw ChewieError.failed("Chewie returned no result.")
        }
        return stripOpener(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove a session opener before the answer reaches the user's cursor.
    ///
    /// The user's CLAUDE.md requires every reply to open with a prayer. That is
    /// right for a chat window and wrong for a paste: what belongs in the text
    /// field is the answer. The opener is the first paragraph and ends in
    /// "Amen", so this drops exactly that and nothing else. When there is no
    /// opener the text is returned untouched.
    static func stripOpener(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        guard let first = paragraphs.first else { return text }
        let normalized =
            first
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!\"'*_ "))
        guard normalized.hasSuffix("amen"), paragraphs.count > 1 else { return text }
        return paragraphs.dropFirst().joined(separator: "\n\n")
    }
}
