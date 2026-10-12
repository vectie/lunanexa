import test from 'node:test';
import assert from 'node:assert/strict';
import { createExtension } from './extension-host.mjs';
import { createRequestHistory } from './recovery-client.mjs';
import { makeHost, result } from './test-host.mjs';

async function setup({ state = 'Running', accepted = true, followup = 'Cancelled' } = {}) {
  const h = makeHost(), calls = [];
  const entry = { baseUrl: h.values.apiBaseUrl, subjectRef: h.values.subjectRef, workloadId: 'vscode-interrupted', createdAt: 1000, mode: 'stream' };
  await createRequestHistory(h.context.globalState).record(entry);
  let gets = 0;
  const extension = createExtension(h.host, { fetchImpl: async (url, options) => {
    calls.push({ url: url.toString(), ...options });
    if (options.method === 'POST') return accepted ? Response.json({ workload_id: entry.workloadId, accepted: true, receipt: 'cancel-receipt' }, { status: 202 }) : new Response('', { status: 503 });
    gets++;
    if (state === 'Missing') return new Response('', { status: 404 });
    if (gets > 1 && followup === 'Unavailable') throw new Error('private failure');
    return Response.json(result(entry.workloadId, gets === 1 ? state : followup));
  } });
  extension.activate(h.context);
  h.host.window.showWarningMessage = async (message, options, action) => { h.events.push({ confirmation: message, options }); return action; };
  return { ...h, entry, calls, extension, run: () => h.commands.get('lunanexa.cancelRecordedRequest')(),
    report: () => h.events.find(e => e.shown)?.shown.content };
}

test('recover interrupted stream: scoped read, exact modal, one cancellation, terminal evidence', async () => {
  const h = await setup(); await h.run();
  assert.deepEqual(h.calls.map(c => c.method), ['GET', 'POST', 'GET']);
  assert.equal(h.calls[1].url, 'https://cluster.example/control/v1/workloads/vscode-interrupted/cancel');
  assert.equal(h.calls[1].body, ''); assert.equal(h.calls[1].headers['X-LunaNexa-Subject'], 'subject-1');
  const modal = h.events.find(e => e.confirmation);
  assert.match(modal.confirmation, /vscode-interrupted/); assert.equal(modal.options.modal, true);
  assert.match(modal.options.detail, /subject-1/); assert.match(modal.options.detail, /Running/);
  assert.match(h.report(), /Cancellation request: accepted/); assert.match(h.report(), /State: Cancelled/);
  assert.equal(h.errors.length, 0);
});
test('accepted cancellation preserves running state rather than inventing termination', async () => {
  const h = await setup({ followup: 'Running' }); await h.run();
  assert.match(h.report(), /State: Running/); assert.match(h.report(), /acceptance is not terminal/);
});
test('accepted cancellation receipt survives unavailable follow-up status', async () => {
  const h = await setup({ followup: 'Unavailable' }); await h.run();
  assert.match(h.report(), /cancel-receipt/); assert.match(h.report(), /outcome remains unknown/);
  assert.doesNotMatch(h.report(), /private failure/);
});
test('unconfirmed cancellation still inspects actual outcome without retrying', async () => {
  const h = await setup({ accepted: false, followup: 'Succeeded' }); await h.run();
  assert.match(h.report(), /Cancellation request: unconfirmed/); assert.match(h.report(), /State: Succeeded/);
  assert.equal(h.calls.filter(c => c.method === 'POST').length, 1);
});
test('terminal history entry and missing status do not offer cancellation', async () => {
  for (const state of ['Succeeded', 'Failed', 'Cancelled', 'Rejected', 'Missing']) {
    const h = await setup({ state }); await h.run();
    assert.equal(h.calls.length, 1); assert.ok(!h.events.some(e => e.confirmation && e.options?.modal));
    assert.equal(h.report(), undefined);
  }
});
test('cancel picker or confirmation sends no mutation', async () => {
  const h = await setup(); h.host.window.showQuickPick = async () => undefined; await h.run(); assert.equal(h.calls.length, 0);
  const j = await setup(); j.host.window.showWarningMessage = async () => undefined; await j.run(); assert.deepEqual(j.calls.map(c => c.method), ['GET']);
});
test('changed context during modal blocks old-scope cancellation', async () => {
  const h = await setup(); h.host.window.showWarningMessage = async (_m, _o, action) => { h.values.subjectRef = 'other'; return action; };
  await h.run(); assert.equal(h.calls.length, 1); assert.match(h.errors[0], /changed/);
});
test('other context history is never offered', async () => {
  const h = await setup(); h.values.subjectRef = 'other'; await h.run(); assert.equal(h.calls.length, 0);
});
test('overlapping invocations do not duplicate mutation and deactivation prevents submission', async () => {
  const h = await setup(); let release; h.host.window.showWarningMessage = () => new Promise(resolve => { release = resolve; });
  const first = h.run(); while (!release) await new Promise(resolve => setImmediate(resolve));
  await h.run(); assert.equal(h.calls.length, 1);
  h.extension.deactivate(); release('Request cancellation'); await first;
  assert.equal(h.calls.length, 1); assert.equal(h.report(), undefined);
});
