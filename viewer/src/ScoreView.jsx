import React, { useEffect, useRef, useState } from 'react'
import { OpenSheetMusicDisplay } from 'opensheetmusicdisplay'

const CHORD_TEXT = /^[A-G][b#]?(m7b5|maj7|dim7|m7|m6|dim|aug|m|6|7)?$/

// OSMD has no per-object font-family/weight hooks, so restyle the rendered
// SVG text nodes that are chord symbols (their text shape is unambiguous).
function styleChordSymbols(container) {
  for (const t of container.querySelectorAll('svg text')) {
    if (CHORD_TEXT.test(t.textContent.trim())) {
      t.setAttribute('font-family', 'Helvetica, Arial, sans-serif')
      t.setAttribute('font-weight', 'bold')
    }
  }
}

export default function ScoreView({ url, label }) {
  const containerRef = useRef(null)
  const osmdRef = useRef(null)
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    async function render() {
      setStatus('loading')
      setError(null)
      try {
        const res = await fetch(url, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`)
        const xml = await res.text()
        if (cancelled) return
        if (!osmdRef.current) {
          osmdRef.current = new OpenSheetMusicDisplay(containerRef.current, {
            autoResize: true,
            drawTitle: true,
            drawComposer: true,
          })
          // Chord symbols with placement="below" land at StaffHeight (4) +
          // this offset — negative pulls them up ONTO the staff (Real Book
          // chord-lane style; only chart-styled staves use below-placement).
          osmdRef.current.EngravingRules.ChordSymbolYOffset = -2.7
          osmdRef.current.EngravingRules.ChordSymbolTextHeight = 3.0
        }
        await osmdRef.current.load(xml)
        if (cancelled) return
        osmdRef.current.render()
        styleChordSymbols(containerRef.current)
        setStatus('ready')
      } catch (e) {
        if (!cancelled) {
          setStatus('error')
          setError(String(e?.message ?? e))
        }
      }
    }
    render()
    return () => { cancelled = true }
  }, [url])

  return (
    <div className="score-view">
      <div className="score-bar">
        <span>{label}</span>
        {status === 'loading' && <span className="dim">rendering…</span>}
        {status === 'error' && <span className="err">render failed: {error}</span>}
      </div>
      <div className="sheet" ref={containerRef} />
    </div>
  )
}
