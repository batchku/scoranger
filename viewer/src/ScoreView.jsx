import React, { useEffect, useRef, useState } from 'react'
import { OpenSheetMusicDisplay } from 'opensheetmusicdisplay'

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
        }
        await osmdRef.current.load(xml)
        if (cancelled) return
        osmdRef.current.render()
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
