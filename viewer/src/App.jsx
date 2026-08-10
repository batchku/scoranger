import React, { useEffect, useRef, useState } from 'react'
import ScoreView from './ScoreView.jsx'

const POLL_MS = 1500

export default function App() {
  const [manifest, setManifest] = useState(null)
  const [selectedSlug, setSelectedSlug] = useState(null)
  // null = follow latest version; a version id = pinned by the user
  const [pinnedVersion, setPinnedVersion] = useState(null)
  const [importing, setImporting] = useState(false)
  const [importError, setImportError] = useState(null)
  const [transposing, setTransposing] = useState(false)
  // part names UNchecked for export (default: none, i.e. export everything)
  const [excludedParts, setExcludedParts] = useState(() => new Set())
  // when set, the main pane shows this source document instead of a version
  const [viewingSource, setViewingSource] = useState(null)
  const fileInputRef = useRef(null)
  const sourceInputRef = useRef(null)

  useEffect(() => {
    let alive = true
    async function poll() {
      try {
        const res = await fetch('/manifest.json', { cache: 'no-store' })
        if (res.ok && alive) setManifest(await res.json())
      } catch {
        /* engine may not have written a manifest yet */
      }
    }
    poll()
    const t = setInterval(poll, POLL_MS)
    return () => { alive = false; clearInterval(t) }
  }, [])

  async function importFile(file, sourceOf = null) {
    setImporting(true)
    setImportError(null)
    try {
      const name = file.name.replace(/\.[^.]+$/, '').replace(/[-_]+/g, ' ')
      const params = new URLSearchParams({ filename: file.name, name })
      if (sourceOf) params.set('source_of', sourceOf)
      const res = await fetch(`/api/import?${params}`, { method: 'POST', body: file })
      const data = await res.json()
      if (!res.ok || data.error) throw new Error(data.error || `HTTP ${res.status}`)
      setSelectedSlug(data.score)
      if (sourceOf && data.source) setViewingSource(data.source)
      else setPinnedVersion(null)
    } catch (e) {
      const msg = String(e?.message ?? e)
      setImportError(msg.includes('Failed to fetch')
        ? 'Engine API not running — start it with: engine/.venv/bin/scor serve'
        : msg)
    } finally {
      setImporting(false)
    }
  }

  const scores = manifest?.scores ?? []
  // Default to the most recently updated score, so fresh work shows up unprompted
  const mostRecent = scores.length
    ? [...scores].sort((a, b) => {
        const ta = a.versions.at(-1)?.time ?? ''
        const tb = b.versions.at(-1)?.time ?? ''
        return tb.localeCompare(ta)
      })[0]
    : null
  const score = scores.find(s => s.slug === selectedSlug) ?? mostRecent
  const versionId = pinnedVersion && score?.versions.some(v => v.id === pinnedVersion)
    ? pinnedVersion
    : score?.latest
  const version = score?.versions.find(v => v.id === versionId)
  const source = viewingSource ? (score?.sources ?? []).find(s => s.id === viewingSource) : null
  const url = source
    ? `/${score.slug}/${source.file}`
    : (score && version ? `/${score.slug}/${version.file}` : null)
  const viewLabel = source
    ? `${score.name} — source ${source.id}: ${source.name}`
    : (score && version ? `${score.name} — ${versionId}` : '')

  return (
    <div className="app">
      <aside className="sidebar">
        <h1>Scoranger</h1>
        <p className="tagline">chat-driven arrangements &middot; prototype</p>

        <div className="section-head">
          <h2>Scores</h2>
          <button className="new-btn" disabled={importing}
                  onClick={() => fileInputRef.current?.click()}>
            {importing ? 'importing…' : 'New…'}
          </button>
          <input ref={fileInputRef} type="file" hidden
                 accept=".musicxml,.xml,.mxl,.mid,.midi"
                 onChange={e => { const f = e.target.files?.[0]; if (f) importFile(f); e.target.value = '' }} />
        </div>
        {importError && <p className="err-note">{importError}</p>}
        {scores.length === 0 && (
          <p className="empty">No scores yet. Click New… to import a MusicXML or MIDI file.</p>
        )}
        <ul className="scores">
          {scores.map(s => (
            <li key={s.slug}>
              <button
                className={score?.slug === s.slug ? 'active' : ''}
                onClick={() => { setSelectedSlug(s.slug); setPinnedVersion(null); setViewingSource(null) }}
              >
                {s.name}
              </button>
            </li>
          ))}
        </ul>

        {score && (
          <>
            <h2>Parts <span className="h2-note">in {versionId}</span></h2>
            {version?.parts ? (
              <ul className="parts">
                {version.parts.map(p => (
                  <li key={p.index} title={p.range ? `range ${p.range[0]}–${p.range[1]}, ${p.notes} notes` : ''}>
                    <span className="pname">{p.name}</span>
                    <span className="pclef">{p.clefs?.join(', ')}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="empty">No parts snapshot for this version.</p>
            )}

            <div className="section-head">
              <h2>Sources</h2>
              <button className="new-btn" disabled={importing}
                      onClick={() => sourceInputRef.current?.click()}>
                Add…
              </button>
              <input ref={sourceInputRef} type="file" hidden
                     accept=".musicxml,.xml,.mxl,.mid,.midi"
                     onChange={e => { const f = e.target.files?.[0]; if (f) importFile(f, score.slug); e.target.value = '' }} />
            </div>
            {(score.sources ?? []).length === 0 && (
              <p className="empty">Other editions/tabs of this piece, for pulling ideas from.</p>
            )}
            <ul className="scores">
              {(score.sources ?? []).map(src => (
                <li key={src.id}>
                  <button className={viewingSource === src.id ? 'active' : ''}
                          title={(src.parts ?? []).map(p => p.name).join(', ')}
                          onClick={() => setViewingSource(viewingSource === src.id ? null : src.id)}>
                    <span className="vid">{src.id}</span> {src.name}
                  </button>
                </li>
              ))}
            </ul>
            {viewingSource && (
              <p className="pin-note">
                Viewing a source (read-only).{' '}
                <a href="#" onClick={e => { e.preventDefault(); setViewingSource(null) }}>Back to arrangement</a>
              </p>
            )}

            <h2>Transpose</h2>
            <div className="transpose-row">
              {[-1, 1].map(n => (
                <button key={n} className="transpose-btn" disabled={transposing}
                        title={`Transpose whole score by ${n} semitone${Math.abs(n) > 1 ? 's' : ''} (new version)`}
                        onClick={async () => {
                          setTransposing(true)
                          setImportError(null)
                          try {
                            const res = await fetch(`/api/transpose?score=${score.slug}&semitones=${n}`, { method: 'POST' })
                            const data = await res.json()
                            if (!res.ok || data.error) throw new Error(data.error || `HTTP ${res.status}`)
                            setPinnedVersion(null) // follow the new latest
                          } catch (e) {
                            const msg = String(e?.message ?? e)
                            setImportError(msg.includes('Failed to fetch')
                              ? 'Engine API not running — start it with: engine/.venv/bin/scor serve'
                              : msg)
                          } finally {
                            setTransposing(false)
                          }
                        }}>
                  {n > 0 ? `♯ +${n}` : `♭ ${n}`}
                </button>
              ))}
              <span className="transpose-note">{transposing ? 'transposing…' : 'semitone'}</span>
            </div>

            {version?.parts && (
              <div className="export-box">
                <h2>Export PDF <span className="h2-note">of {versionId}</span></h2>
                {version.parts.map(p => (
                  <label key={p.index} className="export-check">
                    <input type="checkbox"
                           checked={!excludedParts.has(p.name)}
                           onChange={e => {
                             const next = new Set(excludedParts)
                             e.target.checked ? next.delete(p.name) : next.add(p.name)
                             setExcludedParts(next)
                           }} />
                    {p.name}
                  </label>
                ))}
                <button className="export-btn"
                        disabled={version.parts.every(p => excludedParts.has(p.name))}
                        onClick={() => {
                          const selected = version.parts.filter(p => !excludedParts.has(p.name))
                          const all = selected.length === version.parts.length
                          const params = new URLSearchParams({ score: score.slug, version: versionId, format: 'pdf' })
                          if (!all) params.set('parts', selected.map(p => p.name).join(','))
                          const a = document.createElement('a')
                          a.href = `/api/export?${params}`
                          a.download = ''
                          a.click()
                        }}>
                  Download PDF
                </button>
              </div>
            )}

            <h2>Versions</h2>
            <ul className="versions">
              {[...score.versions].reverse().map(v => (
                <li key={v.id}>
                  <button
                    className={!viewingSource && v.id === versionId ? 'active' : ''}
                    onClick={() => { setViewingSource(null); setPinnedVersion(v.id === score.latest ? null : v.id) }}
                    title={JSON.stringify(v.args)}
                  >
                    <span className="vid">{v.id}</span>
                    <span className="vop">{v.op}</span>
                    {v.id === score.latest && <span className="latest">latest</span>}
                  </button>
                </li>
              ))}
            </ul>
            {pinnedVersion && (
              <p className="pin-note">
                Pinned to {pinnedVersion}.{' '}
                <a href="#" onClick={e => { e.preventDefault(); setPinnedVersion(null) }}>Follow latest</a>
              </p>
            )}
          </>
        )}
      </aside>

      <main className="main">
        {url
          ? <ScoreView url={url} label={viewLabel} />
          : <div className="placeholder">Import a score (New… or the engine CLI) and it appears here.</div>}
      </main>
    </div>
  )
}
