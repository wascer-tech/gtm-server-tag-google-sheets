'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { setup, endpoint, proxyUrl, traceId } = require('./harness.cjs');

const ENVELOPE_KEYS = ['trace_id', 'platform', 'tag_name', 'event_name', 'event_type',
  'request_method', 'request_url', 'request_body', 'response_status', 'response_body', 'duration_ms'];

test('sem x-wascer-log: uma chamada só (proxy), nenhuma ao coletor', async () => {
  const s = setup({ headers: { 'x-wascer-log': undefined } });
  await s.settle();
  assert.equal(s.calls.length, 1);
  assert.equal(s.calls[0].url, proxyUrl);
  assert.equal(s.logs.length, 0);
  assert.equal(s.success, 1);
  assert.equal(s.failure, 0);
});

for (const flag of ['0', 'true', '1 ', '01', '', 1, true]) {
  test('x-wascer-log = ' + JSON.stringify(flag) + ': nenhuma chamada ao coletor', async () => {
    const s = setup({ headers: { 'x-wascer-log': flag } });
    await s.settle();
    assert.equal(s.calls.length, 1);
    assert.equal(s.logs.length, 0);
    assert.equal(s.success, 1);
  });
}

test('x-wascer-log diferente de "1" e erro de rede: nenhuma chamada ao coletor', async () => {
  const s = setup({ headers: { 'x-wascer-log': '0' }, vendorError: true });
  await s.settle();
  assert.equal(s.calls.length, 1);
  assert.equal(s.logs.length, 0);
  assert.equal(s.failure, 1);
});

test('x-wascer-log = "1" e proxy 200: uma cópia para o coletor com o envelope exato', async () => {
  const s = setup({ vendorPending: true });
  assert.equal(s.calls.length, 1, 'só o proxy antes da resposta');
  assert.equal(s.logs.length, 0, 'nada é copiado antes de o proxy responder');
  s.completeVendor();
  await s.settle();
  assert.equal(s.calls.length, 2);
  assert.equal(s.logs.length, 1);
  const [vendor, collector] = s.calls;
  const row = s.logs[0];
  assert.equal(vendor.api, 'callback', 'a entrega continua na forma callback da main');
  assert.equal(collector.url, endpoint);
  assert.equal(collector.api, 'promise');
  assert.equal(collector.options.method, 'POST');
  assert.deepEqual(Object.keys(row).sort(), ENVELOPE_KEYS.slice().sort());
  assert.equal(row.trace_id, traceId);
  assert.equal(row.platform, 'google_sheets');
  assert.equal(row.tag_name, 'Google Sheets');
  assert.equal(row.event_name, 'generate_lead');
  assert.equal(row.event_type, 'generate_lead');
  assert.equal(row.request_method, 'POST');
  assert.equal(row.request_url, vendor.url);
  assert.equal(row.request_url, proxyUrl, 'a URL que a tag de fato chamou (proxy), não a do Google');
  assert.equal(typeof vendor.body, 'string');
  assert.equal(row.request_body, vendor.body, 'string idêntica, byte a byte');
  assert.deepEqual(JSON.parse(row.request_body), {
    spreadsheetName: 'GTM Events - My Site',
    range: "'Leads'!A1%3AZ1",
    type: 'add',
    values: [['private@example.test', 'Maria']]
  }, 'sem máscara');
  assert.equal(row.response_status, 200);
  assert.equal(row.response_body, '{"ok":true}\n');
  assert.ok(Number.isInteger(row.duration_ms) && row.duration_ms >= 0);
  assert.equal(row.duration_ms, 37);
  assert.ok(!JSON.stringify(row).includes('response-credential-never-copy'), 'headers da resposta não vão');
  assert.equal(s.success, 1);
  assert.equal(s.failure, 0);
});

for (const status of [400, 503]) {
  test('proxy ' + status + ': cópia com o status e o body, e a tag chama gtmOnFailure', async () => {
    const s = setup({ status, responseBody: 'unavailable' });
    await s.settle();
    assert.equal(s.logs.length, 1);
    assert.equal(s.logs[0].response_status, status);
    assert.equal(s.logs[0].response_body, 'unavailable');
    assert.equal(s.failure, 1);
    assert.equal(s.success, 0);
  });
}

test('erro de rede (callback sem status nem body): cópia com status 0 e body vazio', async () => {
  const s = setup({ vendorError: true });
  await s.settle();
  assert.equal(s.calls.length, 2);
  assert.equal(s.logs.length, 1);
  assert.deepEqual(Object.keys(s.logs[0]).sort(), ENVELOPE_KEYS.slice().sort());
  assert.equal(s.logs[0].response_status, 0);
  assert.equal(s.logs[0].response_body, '');
  assert.equal(s.logs[0].request_url, proxyUrl);
  assert.equal(s.logs[0].request_body, s.calls[0].body);
  assert.equal(s.failure, 1);
  assert.equal(s.success, 0);
});

test('callback nunca chamado: nenhuma cópia e nenhum resultado novo da tag', async () => {
  const s = setup({ vendorPending: true });
  await s.settle();
  assert.equal(s.calls.length, 1);
  assert.equal(s.logs.length, 0);
  assert.equal(s.success, 0);
  assert.equal(s.failure, 0);
});

test('cenário otimista: gtmOnSuccess uma vez só, e a cópia sai quando o proxy responde', async () => {
  for (const options of [{ status: 200 }, { status: 503 }, { vendorError: true }]) {
    const s = setup({ ...options, data: { useOptimisticScenario: true }, vendorPending: true });
    assert.equal(s.success, 1, 'sucesso antes da resposta');
    assert.equal(s.logs.length, 0);
    s.completeVendor();
    await s.settle();
    assert.equal(s.logs.length, 1);
    assert.equal(s.logs[0].response_status, options.status || 0);
    assert.equal(s.success, 1);
    assert.equal(s.failure, 0);
  }
});

test('campo "Event type (System Log)" preenchido: event_type usa o campo; vazio: usa event_name', async () => {
  const filled = setup({ data: { systemLogEventType: 'lead-planilha' } });
  await filled.settle();
  assert.equal(filled.logs[0].event_type, 'lead-planilha');
  assert.equal(filled.logs[0].event_name, 'generate_lead');
  const empty = setup({ data: { systemLogEventType: '' } });
  await empty.settle();
  assert.equal(empty.logs[0].event_type, 'generate_lead');
  assert.ok(!empty.parameters.some(p => p.name === 'systemLogEventType'), 'não é campo de primeiro nível');
  const group = empty.parameters[empty.parameters.length - 1];
  assert.equal(group.name, 'logsGroup');
  const field = group.subParams[group.subParams.length - 1];
  assert.equal(field.name, 'systemLogEventType', 'último campo do grupo Logs Settings');
  assert.equal(field.type, 'TEXT');
  assert.equal(field.displayName, 'Event type (System Log)');
  assert.equal(field.simpleValueType, true);
});

for (const [label, event] of [['ausente', {}], ['não-string', { event_name: 42 }]]) {
  test('event_name ' + label + ': event_name e event_type vão como string vazia', async () => {
    const s = setup({ event });
    await s.settle();
    assert.equal(s.logs[0].event_name, '');
    assert.equal(s.logs[0].event_type, '');
    assert.equal(s.success, 1);
  });
}

for (const mode of ['reject', 'throw']) {
  test('coletor ' + mode + ': resultado da tag e chamada ao proxy idênticos ao caso sem cópia', async () => {
    for (const options of [{ status: 200 }, { status: 503 }, { vendorError: true }]) {
      const off = setup({ headers: { 'x-wascer-log': undefined }, ...options });
      await off.settle();
      const on = setup({ collectorMode: mode, ...options });
      await on.settle();
      assert.equal(on.logs.length, 1);
      assert.equal(on.success, off.success);
      assert.equal(on.failure, off.failure);
      assert.deepEqual(on.calls.filter(c => c.url !== endpoint), off.calls);
    }
  });
}

test('coletor nunca responde: a tag já chamou gtmOnSuccess', async () => {
  const s = setup({ collectorMode: 'pending' });
  await s.settle();
  assert.equal(s.logs.length, 1);
  assert.equal(s.success, 1);
  assert.equal(s.failure, 0);
});

test('x-wascer-log = "1" sem x-wascer-trace-id: a tag termina normalmente', async () => {
  const s = setup({ headers: { 'x-wascer-trace-id': undefined } });
  await s.settle();
  assert.equal(s.success, 1);
  assert.equal(s.failure, 0);
  assert.equal(s.logs[0].trace_id, '');
});

test('a cópia usa timeout de 500 ms e Content-Type application/json', async () => {
  const s = setup();
  await s.settle();
  const collector = s.calls[1];
  assert.equal(collector.options.timeout, 500);
  assert.deepEqual(collector.options.headers, { 'Content-Type': 'application/json' });
});

test('a tag só tem uma chamada HTTP própria (entrega); não há chamada auxiliar a copiar', async () => {
  const s = setup();
  await s.settle();
  assert.deepEqual(s.calls.map(c => c.url), [proxyUrl, endpoint]);
  assert.equal(s.logs.length, 1);
});

test('console log da tag continua igual (Request e Response) com o System Log ligado', async () => {
  const s = setup({ data: { logType: 'always' } });
  await s.settle();
  const entries = s.consoleLogs.map(args => JSON.parse(args[0]));
  assert.deepEqual(entries.map(e => e.Type), ['Request', 'Response']);
  assert.equal(entries[1].ResponseStatusCode, 200);
  assert.equal(entries[1].ResponseBody, '{"ok":true}\n');
});

test('permissões: só o necessário foi acrescentado', () => {
  const s = setup();
  const names = s.permission('read_request').headerWhitelist.listItem.map(p => p.mapValue[0].string);
  assert.deepEqual(names, ['trace-id', 'x-user-id', 'x-container-identifier', 'x-wascer-log', 'x-wascer-trace-id']);
  assert.equal(s.permission('read_request').headerAccess.string, 'specific');
  const http = s.permission('send_http');
  assert.equal(http.allowedUrls.string, 'specific');
  assert.deepEqual(http.urls.listItem.map(p => p.string), ['https://waster.sourei.com.br/*', endpoint]);
  const eventData = s.permission('read_event_data');
  assert.equal(eventData.eventDataAccess.string, 'specific');
  assert.deepEqual(eventData.keyPatterns.listItem.map(p => p.string), ['event_name']);
});

test('com a cópia desligada, a chamada ao proxy é idêntica à do template da main', async () => {
  // fixture = seção SANDBOXED_JS_FOR_SERVER de `git show main:template.tpl` antes desta mudança
  const mainCode = fs.readFileSync(path.resolve(__dirname, 'fixtures/sandboxed-js.main.txt'), 'utf8');
  const variants = [
    {},
    { type: 'update', sheetName: '', rows: 'B2:C2' },
    { useOptimisticScenario: true },
    { useOptimisticScenario: 'true', dataList: undefined },
    { logType: 'always' }
  ];
  for (const data of variants) {
    const outcomes = [{ status: 200 }, { status: 302 }, { status: 400 }, { status: 503 }, { vendorError: true }];
    for (const outcome of outcomes) {
      const before = setup({ code: mainCode, data, ...outcome, headers: { 'x-wascer-log': undefined } });
      const after = setup({ data, ...outcome, headers: { 'x-wascer-log': undefined } });
      const withLog = setup({ data, ...outcome });
      await Promise.all([before.settle(), after.settle(), withLog.settle()]);
      assert.equal(before.calls.length, 1);
      assert.equal(before.calls[0].api, 'callback');
      assert.deepEqual(after.calls, before.calls);
      assert.deepEqual(withLog.calls[0], before.calls[0], 'ligar o log não muda a chamada ao proxy');
      assert.equal(after.success, before.success);
      assert.equal(after.failure, before.failure);
      assert.equal(withLog.success, before.success);
      assert.equal(withLog.failure, before.failure);
      assert.deepEqual(after.consoleLogs, before.consoleLogs);
      assert.deepEqual(withLog.consoleLogs, before.consoleLogs);
    }
  }
});
