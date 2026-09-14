import Foundation

/// The two decisions between a downloaded shared entry and an arrangement in
/// this library: which engine op takes the file, and where the slug is in what
/// comes back. Pure, so both are pinned by tests against the shapes the bridge
/// actually returns.
///
/// Both were wrong on 0.7.3 build 188, in Ali's wife's hands. Every MusicXML
/// entry downloaded and imported successfully -- a score was created in her
/// library -- and then the caller read `result["score"]` as a dictionary when
/// the bridge returns a string, threw the payload away as unusable, and never
/// filed the arrangement into the set list. The PDF entry went to the `import`
/// op, which parses notation and cannot take a PDF, when `import-pdf` exists
/// for exactly that. She joined a set list of six and got a row with none.
enum SharedEntryImport {

    /// `import-pdf` for a scan, `import` for notation -- the same split the
    /// app's own import makes, keyed the same way, on the file's suffix.
    static func op(for file: URL) -> String {
        file.pathExtension.lowercased() == "pdf" ? "import-pdf" : "import"
    }

    /// The slug of the arrangement an import op made.
    ///
    /// Both ops return `{"score": "<slug>", "version": "<id>", ...}` -- `score`
    /// is the slug as a STRING. That is the bridge's contract
    /// (`check_bridge_import.py` holds it there), and this is the only reading
    /// of it on this side.
    static func slug(in result: [String: Any]) -> String? {
        guard let slug = result["score"] as? String, !slug.isEmpty else { return nil }
        return slug
    }
}
