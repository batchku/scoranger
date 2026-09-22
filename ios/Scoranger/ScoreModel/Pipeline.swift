import Foundation

/// What Settings' "How Scoranger works" says, as data.
///
/// The prose, the diagram's stages and the list of open-source projects the
/// app is built on all live here, in ScoreModel, for the reason `ChatTools`
/// does: this bundle's tests have no host app, and these are the two things in
/// the section worth asserting. The CREDITS especially -- several of these
/// licences require attribution, so a name or a licence dropped by accident is
/// a licence breach rather than a typo, and a test is cheaper than remembering.
///
/// Nothing here draws. `HowItWorks.swift` is the view.
enum Pipeline {

    // MARK: - Where a step runs

    /// The fact a musician on a stage with no wifi actually needs.
    enum RunsOn: String {
        case onDevice   = "on this iPad"
        case network    = "over the network"
        /// Not a step the app performs -- what the reader brings.
        case yours      = ""

        var label: String? { self == .yours ? nil : rawValue }
    }

    // MARK: - The diagram

    /// One box in the diagram.
    struct Stage: Identifiable {
        let id: String
        let title: String
        /// One or two sentences. This is read aloud as the box's value.
        let detail: String
        let locale: RunsOn
        /// What travels down the arrow INTO this stage. `nil` on the first one,
        /// which nothing points at.
        let arrival: String?
        /// A step that joins the chain here rather than sitting in it -- the
        /// chat agent, which calls the engine and is not on the road the music
        /// travels. Drawn indented, so the shape says "joins" and not "then".
        let branch: Branch?

        init(id: String, title: String, detail: String, locale: RunsOn,
             arrival: String? = nil, branch: Branch? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.locale = locale
            self.arrival = arrival
            self.branch = branch
        }
    }

    struct Branch {
        let id: String
        let title: String
        let detail: String
        let locale: RunsOn
        /// What the branch hands to the stage it joins.
        let hands: String
    }

    /// The diagram, top to bottom.
    ///
    /// A simplification of the one in README.md, which groups the system six
    /// ways for somebody who is going to read the code. The groups a musician
    /// does not need are folded in; the SHAPE is not touched, because the shape
    /// is the honest part: two roads in and only one of them guesses, one
    /// engine that alone changes notation, a version written for every step,
    /// and an agent that calls that engine instead of writing music itself.
    static let stages: [Stage] = [
        Stage(id: "sources",
              title: "What you bring in",
              detail: "A MusicXML or MIDI file, a PDF, or a photograph of a page.",
              locale: .yours),
        Stage(id: "omr",
              title: "Reading the page",
              detail: "Only for a PDF or a photograph. Recognition software looks at "
                    + "the picture, finds the staves and the notes, and writes out the "
                    + "notation it thinks is there. MusicXML and MIDI skip this step: "
                    + "they are notation already.",
              locale: .network,
              arrival: "a picture of a page"),
        Stage(id: "engine",
              title: "The score engine",
              detail: "The only part of Scoranger that changes notation. Transposing, "
                    + "harmonising within a key, merging staves, fitting a line to an "
                    + "instrument's range and clef: each one is written-out music "
                    + "theory that does the same thing every time.",
              locale: .onDevice,
              arrival: "notation",
              branch: Branch(id: "agent",
                             title: "The chat agent",
                             detail: "Reads the score's parts, ranges and keys, works out "
                                   + "which operations answer what you asked for, and "
                                   + "reports what they did. It writes no notation.",
                             locale: .network,
                             hands: "the name of an operation, never notes")),
        Stage(id: "versions",
              title: "A new version, every time",
              detail: "An operation never edits what you had. It writes a new version "
                    + "beside it, labelled with the operation that made it, and nothing "
                    + "earlier is touched. Going back is reading an older one.",
              locale: .onDevice,
              arrival: "the changed score"),
        Stage(id: "page",
              title: "The page you read",
              detail: "The version you are looking at, engraved into the staves, "
                    + "noteheads and beams on screen, and into anything you export.",
              locale: .onDevice,
              arrival: "the version you chose"),
    ]

    // MARK: - The prose

    /// A titled block of the explanation. The section is these in order.
    struct Passage: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    static let passages: [Passage] = [
        Passage(id: "in", title: "Getting a score in", body:
            "A MusicXML or MIDI file is notation already, so it comes in as it is and "
          + "nothing has to be guessed.\n\n"
          + "A PDF or a photograph is a picture of notation, which is a different "
          + "problem. It goes through optical music recognition: software looks at the "
          + "image, finds the staves, the noteheads, the stems and the rests, and "
          + "writes out the notation it thinks the page holds. That is a reading, and "
          + "readings are wrong sometimes. Ties, dynamics and anything handwritten are "
          + "where a scan usually needs correcting. What you get is a draft you can "
          + "edit, not a transcription you have to trust."),
        Passage(id: "ops", title: "How an arrangement is made", body:
            "Every arrangement operation in Scoranger is music theory written out as "
          + "code: transpose by an interval, move a line by scale degrees so it stays "
          + "in the key, merge two staves into one, fit a part to an instrument's range "
          + "and pick the clef a player expects. Each one is tested and does the same "
          + "thing every time you run it.\n\n"
          + "None of it is written by a language model, and that is deliberate. Models "
          + "are good at talking about music and unreliable at writing it down: asked "
          + "to edit notation as text they corrupt it. Asked instead to call an "
          + "operation by name, they are accurate. So the model chooses; the code "
          + "performs."),
        Passage(id: "versions", title: "Nothing is overwritten", body:
            "An operation does not edit your score. It writes a new version beside the "
          + "old one and points the arrangement at it. The history is the whole chain, "
          + "each step labelled with the operation that made it, and you can go back to "
          + "any of them.\n\n"
          + "That is what makes it safe to try something. Undoing is not a repair; it "
          + "is reading an earlier version."),
        Passage(id: "chat", title: "What the chat agent does", body:
            "Ask for an arrangement in words and a language model reads the score's "
          + "structure -- its parts, their ranges, the keys, the bar count -- plans a "
          + "sequence of operations, and calls them by name. It tells you what it did, "
          + "including what it could not do.\n\n"
          + "It never writes a note itself. If the tools it has cannot do what you "
          + "asked, it says so instead of inventing notation."),
        Passage(id: "offline", title: "What needs the network, and what does not", body:
            "The engine is not on a server somewhere. Python, the music library and the "
          + "engraver are inside this app and run on this iPad. Importing, arranging, "
          + "versioning, engraving, exporting, marking up with the pencil and playback "
          + "all work with the network switched off.\n\n"
          + "Two things do not. Scanning a PDF or a photograph sends it to a "
          + "recognition service, and the chat agent talks to a language model over the "
          + "internet.\n\n"
          + "So on a stage with no wifi you can still open, read, play, transpose and "
          + "export everything already in your library. You cannot scan a new PDF, and "
          + "you cannot ask the agent for anything."),
    ]

    // MARK: - Credits

    /// An open-source project this app ships or depends on.
    ///
    /// `licence` is the identifier the project's own licence file states, read
    /// out of the tree rather than remembered: BSD-3-Clause and LGPL-3.0 are
    /// not interchangeable and the obligation differs. `role` is one phrase on
    /// what it does FOR THIS APP, not what the project is.
    struct Credit: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let licence: String
        let role: String
    }

    struct CreditGroup: Identifiable {
        let id: String
        let title: String
        /// One sentence about the group, where the group needs one.
        let note: String?
        let credits: [Credit]
    }

    /// What Scoranger is built on.
    ///
    /// Verified against `ios/project.yml`, `Package.resolved`, the vendored
    /// trees under `ios/Vendor/`, `ios/PythonApp/app_packages/` and the
    /// `.dist-info` metadata of each Python package -- not copied from
    /// README.md. What README.md got wrong, and this does not:
    ///
    /// - OpenSheetMusicDisplay is NOT in this app. It renders the desktop
    ///   prototype's web viewer and nothing else; the only mention of it under
    ///   `ios/` is a comment. Crediting it on an iPad screen would be a
    ///   courtesy to a project that is not here.
    /// - Audiveris does not run on the iPad and never has. It is a Cloud Run
    ///   container the app POSTs a PDF to, which is what makes scanning the one
    ///   import that needs a network.
    /// - pypdf ships inside the app and README.md lists it as desktop-only. It
    ///   is not optional: a book IS a PDF.
    /// - Verovio brings six music fonts and seven C libraries with it, all of
    ///   which compile into or ship beside the binary, and none of which were
    ///   named anywhere.
    /// - The sound bank, the three interface typefaces, and everything the
    ///   Firebase SDK pulls in behind it were all unlisted.
    ///
    /// Two gaps are known and are NOT fixed by this screen, recorded in
    /// BACKLOG.md: `ios/scripts/vendor_engine.sh` deletes every `.dist-info`
    /// on the way into the bundle, so the Python packages' licence TEXTS do
    /// not ship beside them; and the C libraries inside BeeWare's Python build
    /// carry no licence files in this tree, so they are named here by their
    /// own names and versions rather than given an identifier nobody read.
    static let creditGroups: [CreditGroup] = [
        CreditGroup(id: "omr", title: "Reading a scanned page", note:
            "This is the one that is not on your iPad.",
            credits: [
            Credit(name: "Audiveris", licence: "AGPL-3.0",
                   role: "reads a picture of a page and writes out the notation. "
                       + "It runs unmodified, on its own, on a server."),
        ]),
        CreditGroup(id: "engine", title: "Changing the notation", note:
            "All of this runs inside the app, on this iPad.",
            credits: [
            Credit(name: "music21", licence: "BSD-3-Clause",
                   role: "the score itself: parts, pitches, keys, meters. The only "
                       + "code in Scoranger that changes a note."),
            Credit(name: "CPython 3.14", licence: "PSF-2.0",
                   role: "runs music21 on the iPad. BeeWare's iOS build, which "
                       + "carries OpenSSL, XZ, Zstandard, bzip2, libffi and "
                       + "mpdecimal with it under their own licences."),
            Credit(name: "pypdf", licence: "BSD-3-Clause",
                   role: "counts the pages of a PDF book and pulls one out."),
            Credit(name: "requests", licence: "Apache-2.0",
                   role: "music21 asks for things over the web with it."),
            Credit(name: "urllib3", licence: "MIT", role: "what requests is built on."),
            Credit(name: "certifi", licence: "MPL-2.0",
                   role: "the list of certificate authorities those requests trust."),
            Credit(name: "idna", licence: "BSD-3-Clause",
                   role: "domain names that are not written in ASCII."),
            Credit(name: "chardet", licence: "0BSD",
                   role: "guesses the text encoding of a file that does not say."),
            Credit(name: "charset-normalizer", licence: "MIT",
                   role: "the same guess, the other way round."),
            Credit(name: "joblib", licence: "BSD-3-Clause",
                   role: "music21 remembers slow work with it."),
            Credit(name: "jsonpickle", licence: "BSD-3-Clause",
                   role: "writes music21's objects out and reads them back."),
            Credit(name: "more-itertools", licence: "MIT",
                   role: "the loops music21 does not want to write again."),
            Credit(name: "webcolors", licence: "BSD-3-Clause",
                   role: "turns a colour's name into a colour."),
        ]),
        CreditGroup(id: "page", title: "Drawing the page", note: nil, credits: [
            Credit(name: "Verovio", licence: "LGPL-3.0",
                   role: "engraves the notation: staves, noteheads, beams, slurs, "
                       + "and where every one of them sits."),
            Credit(name: "Leipzig, Bravura, Gootville, Petaluma, Leland, Liberation",
                   licence: "SIL OFL-1.1",
                   role: "the music fonts Verovio draws with. The shapes of the "
                       + "notes are these."),
            Credit(name: "pugixml, jsonxx, miniz-cpp, humlib, tuning-library",
                   licence: "MIT and BSD-2-Clause",
                   role: "compiled inside Verovio: reading files, opening "
                       + "compressed ones, tuning."),
            Credit(name: "SwiftDraw", licence: "zlib",
                   role: "turns Verovio's drawing into the page on screen and the "
                       + "pages you export."),
        ]),
        CreditGroup(id: "sound", title: "Sound", note: nil, credits: [
            Credit(name: "GeneralUser GS, by S. Christian Collins",
                   licence: "GeneralUser GS License v2.0",
                   role: "every instrument you hear. iOS ships no sound bank an "
                       + "app may use, so this one travels inside Scoranger."),
        ]),
        CreditGroup(id: "type", title: "The lettering", note: nil, credits: [
            Credit(name: "Inter", licence: "SIL OFL-1.1", role: "the interface text."),
            Credit(name: "IBM Plex Mono", licence: "SIL OFL-1.1",
                   role: "version labels, timings, anything in columns."),
            Credit(name: "Space Grotesk", licence: "SIL OFL-1.1",
                   role: "titles and the arrangement numerals."),
        ]),
        CreditGroup(id: "account", title: "An account, and shared set lists", note:
            "Only if you sign in. Signed out, none of this runs.",
            credits: [
            Credit(name: "Firebase Apple SDK", licence: "Apache-2.0",
                   role: "the account, the shared set lists, and the files they carry."),
            Credit(name: "Google Sign-In", licence: "Apache-2.0",
                   role: "signing in with a Google account."),
            Credit(name: "gRPC and BoringSSL", licence: "Apache-2.0",
                   role: "how Firebase talks, and how that talk is encrypted."),
            Credit(name: "Abseil", licence: "Apache-2.0", role: "gRPC is built on it."),
            Credit(name: "LevelDB", licence: "BSD-3-Clause",
                   role: "where Firebase keeps its copy on the device."),
            Credit(name: "nanopb", licence: "zlib", role: "small messages, in a small space."),
            Credit(name: "SwiftProtobuf", licence: "Apache-2.0",
                   role: "the shape those messages take."),
            Credit(name: "GoogleUtilities, GTMSessionFetcher, GTMAppAuth, AppAuth, Promises",
                   licence: "Apache-2.0",
                   role: "what the two SDKs above are assembled from."),
        ]),
        CreditGroup(id: "chat", title: "The chat", note: nil, credits: [
            Credit(name: "OpenRouter", licence: "not open source; a service",
                   role: "carries your question to whichever language model is "
                       + "chosen in Settings. No code of theirs is in the app."),
        ]),
    ]

    /// Every credit, flat -- for counting, and for the tests.
    static var credits: [Credit] { creditGroups.flatMap(\.credits) }
}
