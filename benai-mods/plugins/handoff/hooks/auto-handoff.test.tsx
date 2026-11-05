import { expect, mock, test } from 'claude-code/testing'

const HANDOFF = '# Handoff: Build the refresh mod\n\nContinue work in `~/vault`. Goal: finish it.\n\n## Next steps\n1. Test it.'

type Rig = { kit: any; tokens: { value: number }; failFork: { value: boolean }; misses: { value: number }; completeOnAbort: boolean; onFork: ($: any) => void | Promise<void>; files: Record<string, string>; seq: string[]; dirty: { value: string }; agents: { value: unknown[] } }

/** Mocks every $ call the automatic handoff makes. `seq` records the order of the calls that matter. */
function rig(on: Parameters<NonNullable<Parameters<typeof test>[2]>>[1], start: number, over: Partial<Rig> = {}) {
  const tokens = over.tokens ?? { value: start }
  const failFork = over.failFork ?? { value: false }
  const misses = over.misses ?? { value: 0 }
  const files: Record<string, string> = over.files ?? {}
  const seq: string[] = over.seq ?? []
  const dirty = over.dirty ?? { value: ' M src/a.ts' }
  const agents = over.agents ?? { value: [] as unknown[] }
  const captured: { submitted: string; abortedWith: unknown } = { submitted: '', abortedWith: undefined }

  on('session.start', async ($, e) => ({ cwd: e.cwd }) as never)
  on('command.register', async () => ({ value: undefined }) as never)
  on('tool.register', async () => ({ value: { tool: 'mcp__handoff__refresh' } }) as never)
  const clock = mock.clock(on, { now: 1_000_000 })
  on('session.id', async () => ({ value: 'sid' }) as never)
  on('session.cwd', async () => ({ value: '/Users/test/vault' }) as never)
  on('session.usage', async () => ({ value: { context: { tokens: tokens.value, window: 300_000 } } }) as never)
  on('session.messages', async () => ({ value: [{ role: 'user', text: 'Build a refresh mod', toolUses: [] }] }) as never)
  on('model.fork', async $ => {
    seq.push('fork')
    await over.onFork?.(over.kit)
    if (misses.value > 0) {
      misses.value -= 1
      return { value: { isAnswered: false, reason: 'nothing-to-fork' } } as never
    }
    if (failFork.value) return { value: { isAnswered: false, reason: 'api-error', status: 529 } } as never
    return { value: { isAnswered: true, text: HANDOFF, usage: {} } } as never
  })
  on('fs.exists', async ($, e) => ({ value: (e as { path: string }).path in files }) as never)
  on('fs.write', async ($, e) => {
    const { path, text } = e as { path: string; text: string }
    files[path] = text
    return { value: undefined } as never
  })
  on('fs.read', async ($, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('process.run', async ($, e) => {
    const { argv } = e as { argv: readonly string[] }
    return { value: { exitCode: 0, stdout: argv.includes('status') ? dirty.value : '', stderr: '' } } as never
  })
  on('store.get', async () => ({ value: undefined }) as never)
  on('store.set', async () => ({ value: undefined }) as never)
  on('agent.list', async () => ({ value: agents.value }) as never)
  on('turn.abort', async ($, e) => {
    seq.push('abort')
    captured.abortedWith = e
    // The engine ends the aborted turn right away.
    if (over.completeOnAbort !== false) await over.kit?.turn.complete({ answer: '', isAborted: true } as never)
    return { value: undefined } as never
  })
  on('command.run', { command: 'clear' }, async () => {
    seq.push('clear')
    return { text: '' } as never
  })
  on('prompt.submit', async ($, e) => {
    seq.push('submit')
    captured.submitted = (e as { text: string }).text
    return { text: captured.submitted } as never
  })
  on('turn.start', async ($, e) => ({ turnId: (e as { turnId: string }).turnId }) as never)
  on('turn.complete', async () => ({ text: '' }) as never)
  on('ui.render', { component: 'AbovePrompt' }, async ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>REST</Text>
  })
  return { clock, files, seq, dirty, agents, captured, tokens, failFork, misses }
}

for (const surface of ['desktop', 'terminal'] as const) {
  test(`at 230k it waits for a safe point, stops the agent, writes the handoff, clears and sends it (${surface})`, { timeoutMs: 60000 }, async ($, on) => {
    const { clock, files, seq, dirty, agents, captured } = rig(on, 235_000, { kit: $ })
    await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface, isInteractive: true } as never)
    await $.turn.start({ text: 'work', turnId: 'T1' } as never)

    // Uncommitted files: nothing is stopped.
    await clock.advance(12_000)
    expect(seq, 'dirty tree: no abort, no clear').toEqual([])

    // Committed, but a subagent is still running: still waiting.
    dirty.value = ''
    agents.value = [{ id: 'a1' }]
    await clock.advance(12_000)
    expect(seq, 'subagent running: no abort, no clear').toEqual([])

    // Safe point: abort first, then the handoff from that moment, then clear, then send.
    agents.value = []
    await clock.advance(30_000)
    expect(seq, 'abort, then the model step, then clear, then submit').toEqual(['abort', 'fork', 'clear', 'submit'])
    expect(JSON.stringify(captured.abortedWith), 'abort carries the turn id').toContain('T1')
    expect(captured.submitted, 'the handoff is the first message of the clean chat').toContain('# Handoff: Build the refresh mod')

    // One launch per stretch: no second handoff while the count stays high.
    await clock.advance(30_000)
    expect(seq.filter(s => s === 'submit'), 'sent once').toHaveLength(1)
    const log = Object.entries(files).find(([k]) => k.endsWith('/handoff.log'))?.[1] ?? ''
    expect(log, 'the wait is logged').toContain('waiting for a safe point')
    expect(log, 'the send is logged').toContain('handoff sent into the cleared chat')
  })
}

test('with no turn running there is nothing to abort: the handoff is written, then clear and send', { timeoutMs: 60000 }, async ($, on) => {
  const { clock, seq, dirty } = rig(on, 235_000)
  dirty.value = ''
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await clock.advance(40_000)
  expect(seq, 'idle chat: no abort').toEqual(['fork', 'clear', 'submit'])
})

test('a tree that turns dirty while the handoff is written is not cleared', { timeoutMs: 60000 }, async ($, on) => {
  const dirty = { value: '' }
  const { clock, seq, files } = rig(on, 235_000, { dirty, onFork: () => { dirty.value = ' M src/late.ts' } })
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await clock.advance(40_000)
  expect(seq, 'no clear and no submit after the tree changed').toEqual(['fork'])
  const log = Object.entries(files).find(([k]) => k.endsWith('/handoff.log'))?.[1] ?? ''
  expect(log, 'the refusal is logged').toContain('not cleared')
})

test('at the hard limit with no safe point only the handoff is written: no abort, no clear', { timeoutMs: 60000 }, async ($, on) => {
  const { clock, seq } = rig(on, 275_000)
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await $.turn.start({ text: 'work', turnId: 'T1' } as never)
  await clock.advance(30_000)
  expect(seq, 'handoff only').toEqual(['fork'])
  await clock.advance(30_000)
  expect(seq.filter(s => s === 'fork'), 'one handoff, not one per poll').toHaveLength(1)
})

test('a message typed while the handoff is written starts a new turn: the chat is not cleared', { timeoutMs: 60000 }, async ($, on) => {
  const dirty = { value: '' }
  const { clock, seq, files } = rig(on, 235_000, { kit: $, dirty, onFork: async $ => { await $.turn.start({ text: 'new message', turnId: 'T2' } as never) } })
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await clock.advance(40_000)
  expect(seq, 'no clear and no submit over a live turn').toEqual(['fork'])
  const log = Object.entries(files).find(([k]) => k.endsWith('/handoff.log'))?.[1] ?? ''
  expect(log, 'the refusal is logged').toContain('not cleared')
})

test('an abort that does not land stops the run before the handoff, and the next poll tries again', { timeoutMs: 60000 }, async ($, on) => {
  const dirty = { value: '' }
  const { clock, seq } = rig(on, 235_000, { dirty, completeOnAbort: false })
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await $.turn.start({ text: 'work', turnId: 'T1' } as never)
  await clock.advance(30_000)
  expect(seq.includes('fork'), 'no handoff while the turn still runs').toBe(false)
  expect(seq.filter(s => s === 'abort').length, 'the abort is retried').toBeGreaterThan(1)
  expect(seq.includes('clear'), 'no clear').toBe(false)
})

test('a failed run leaves its panel up, and the automatic handoff re-arms once the count drops', { timeoutMs: 60000 }, async ($, on) => {
  const dirty = { value: '' }
  const tokens = { value: 235_000 }
  const failFork = { value: true }
  const { clock, seq } = rig(on, 235_000, { dirty, tokens, failFork })
  await $.session.start({ source: 'startup', cwd: '/Users/test/vault', surface: 'desktop', isInteractive: true } as never)
  await clock.advance(30_000)
  expect(seq, 'the first run failed at the model step').toEqual(['fork'])
  await clock.advance(30_000)
  expect(seq.filter(s => s === 'fork'), 'no retry loop while the count stays high').toHaveLength(1)

  // A compaction or /clear brings the count down; then it climbs again.
  failFork.value = false
  tokens.value = 60_000
  await clock.advance(10_000)
  tokens.value = 235_000
  await clock.advance(40_000)
  expect(seq.slice(-3), 'armed again: handoff, clear, send').toEqual(['fork', 'clear', 'submit'])
})

test('nothing-to-fork right after the abort is retried, then the handoff is written and sent', { timeoutMs: 60000 }, async ($, on) => {
  const misses = { value: 2 }
  const { clock, seq, captured } = rig(on, 235_000, { kit: $, dirty: { value: '' }, misses })
  await $.session.start({ cwd: '/Users/test/vault' } as never)
  await $.turn.start({ text: 'work', turnId: 'T1' } as never)
  await clock.advance(30_000)
  await clock.advance(30_000)
  expect(seq.filter(x => x === 'fork').length, 'two misses and one answer').toBe(3)
  expect(seq).toContain('clear')
  expect(captured.submitted).toContain('# Handoff:')
})
