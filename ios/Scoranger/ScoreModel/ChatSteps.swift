import Foundation

/// The line the reader watches while the agent works.
///
/// Lifted out of LocalChat so it can be tested: the test bundle has no host
/// app and compiles ScoreModel in whole, while LocalChat itself pulls in the
/// embedded engine, the Keychain and the network. The titles are pure over the
/// tool name and its arguments, so there is nothing here that needs any of it.
///
/// They say what the MUSIC is doing, not what the tool is called: a reader who
/// asked for a harmony a sixth below should see "Harmonising a sixth below, in
/// key" and not "Transpose diatonic".
enum ChatSteps {

    static func stepTitle(name: String, argsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any]) ?? [:]
        func s(_ key: String) -> String? { args[key] as? String }
        /// A number the model may have written either way: JSON `3` or the
        /// string "3". Both arrive from real providers.
        func n(_ key: String) -> String? {
            if let v = args[key] as? String { return v }
            if let v = args[key] as? NSNumber { return v.stringValue }
            return nil
        }
        /// The four marks `add_element` writes, named the way a reader would
        /// say them rather than the way the tool spells them.
        func mark(_ kind: String?) -> String {
            switch kind {
            case "dynamic": return "dynamic"
            case "text": return "text mark"
            case "fermata": return "fermata"
            case "articulation": return "articulation"
            case "diagram": return "chord diagram"
            case "tab": return "tab column"
            default: return "chord name"
            }
        }
        switch name {
        case "get_score_info": return "Reading the score"
        case "list_versions": return "Checking version history"
        case "analyze_harmony": return "Analyzing the harmony"
        case "transpose": return "Transposing \(s("interval") ?? "")"
        case "respell": return "Respelling with \(s("prefer") ?? "flats")"
        case "change_instrument": return "\(s("part") ?? "part") → \(s("to_instrument") ?? "new instrument")"
        case "rename_part": return "Renaming \(s("part") ?? "part") to \(s("name") ?? "")"
        case "set_structure":
            let what = s("kind") ?? "mark"
            if s("remove") == "true" { return "Removing the \(what)" }
            if let to = s("move_to") { return "Moving the \(what) to bar \(to)" }
            return "Adding \(what) at bar \(s("measure") ?? "?")"
        case "adjust_element":
            let what = mark(s("kind"))
            if s("reset") == "true" || args["reset"] as? Bool == true {
                return "Putting the \(what) back"
            }
            // Relative first, because relative is the interface: "make it
            // bigger" is a multiple of the engraved size, and a point value
            // only arrives from a caller that already holds one.
            if let scale = n("scale") { return "Resizing the \(what) to \(scale)x" }
            if let size = n("size") { return "Setting the \(what) to \(size)pt" }
            return "Moving the \(what)"
        case "add_element":
            return "Adding a \(mark(s("kind"))) at bar \(n("measure") ?? "?")"
        case "move_element":
            return "Moving the \(mark(s("kind"))) to bar \(n("to_measure") ?? "?")"
        case "duplicate_element":
            return "Copying the \(mark(s("kind"))) into bar \(n("to_measure") ?? "?")"
        case "strip_notes":
            return "Clearing the notes from \(s("part") ?? "the part")"
        case "guitar_tablature":
            return s("clear") == "true"
                ? "Removing the tab from \(s("part") ?? "the part")"
                : "Writing tab under \(s("part") ?? "the part")"
        case "guitar_chord_diagrams":
            return s("clear") == "true"
                ? "Removing chord diagrams from \(s("part") ?? "the part")"
                : "Drawing chord diagrams over \(s("part") ?? "the part")"
        case "penny_whistle_fingerings":
            return s("clear") == "true"
                ? "Removing whistle fingerings from \(s("part") ?? "the part")"
                : "Writing whistle fingerings under \(s("part") ?? "the part")"
        case "set_metadata":
            if let t = s("title") { return "Titling the arrangement \u{201C}\(t)\u{201D}" }
            return "Updating the arrangement's credits"
        case "transpose_diatonic", "transpose_diatonic_elements":
            // the reader asked for a harmony, so the step says harmony -- not
            // "transpose diatonic", which is the tool's name and not the music
            let degrees = s("degrees") ?? ""
            let steps = Int(degrees.replacingOccurrences(of: "+", with: ""))
            let named = steps.map { step -> String in
                let names = [2: "second", 3: "third", 4: "fourth", 5: "fifth",
                             6: "sixth", 7: "seventh", 8: "octave", 9: "ninth",
                             10: "tenth", 12: "twelfth"]
                let where_ = step < 0 ? "below" : "above"
                guard let name = names[abs(step)] else {
                    // no article: "13 steps below" reads, "a 13 steps below" does not
                    return "\(abs(step)) steps \(where_)"
                }
                let article = "aeiou".contains(name.first ?? "x") ? "an" : "a"
                return "\(article) \(name) \(where_)"
            } ?? degrees
            return "Harmonising \(named), in key"
        case "change_clef": return "Setting \(s("part") ?? "part") to \(s("clef") ?? "") clef"
        case "keep_parts", "remove_parts":
            let parts = (args["parts"] as? [String])?.joined(separator: ", ") ?? ""
            return name == "keep_parts" ? "Keeping only \(parts)" : "Removing \(parts)"
        case "merge_parts": return "Merging into \(s("new_name") ?? "one staff")"
        case "split_bass": return "Splitting bass and chords"
        case "octave_shift": return "Octave shift: \(s("part") ?? "part")"
        case "check_range": return "Checking range of \(s("part") ?? "part")"
        case "set_chords": return "Writing chord symbols"
        case "chart_style": return "Applying chart styling"
        case "pull_part": return "Pulling \(s("part") ?? "part") from \(s("from_ref") ?? "source")"
        case "absorb_part": return "Folding \(s("source") ?? "part") into \(s("target") ?? "part")"
        case "flatten_voices": return "Flattening voices in \(s("part") ?? "part")"
        case "consolidate_ties": return "Cleaning up ties"
        case "limit_part": return "Limiting \(s("part") ?? "part") for playability"
        case "simplify_repeats": return "Simplifying repeated bass notes"
        default:
            return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

}
