'use strict';
// Runs the sandboxed server code of template.tpl in node:vm with permission-aware
// API doubles. Not a Google sandbox compiler and not proof of live sGTM delivery.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const endpoint = 'https://system-log.wascer.internal/log';
const proxyUrl = 'https://waster.sourei.com.br/google-sheets/proxy';
const traceId = '12345678-1234-4234-8234-123456789abc';
const templatePath = path.resolve(__dirname, '../template.tpl');

function section(text, name) {
  return text.split('___' + name + '___')[1].split(/___[A-Z_]+___/)[0].trim();
}

function readTemplate() {
  const text = fs.readFileSync(templatePath, 'utf8');
  return {
    info: JSON.parse(section(text, 'INFO')),
    parameters: JSON.parse(section(text, 'TEMPLATE_PARAMETERS')),
    permissions: JSON.parse(section(text, 'SERVER_PERMISSIONS')),
    code: section(text, 'SANDBOXED_JS_FOR_SERVER')
  };
}

const safeJSON = {
  stringify: JSON.stringify,
  parse(value) { try { return JSON.parse(value); } catch (e) { return undefined; } }
};

function urlAllowed(pattern, url) {
  const source = pattern.split('*').map(part => part.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*');
  return new RegExp('^' + source + '$').test(url);
}

// options.code runs another program (e.g. the fixture from main) against the same doubles.
function setup(options = {}) {
  const template = readTemplate();
  const permissions = template.permissions;
  function permission(name) {
    const entry = permissions.find(p => p.instance.key.publicId === name);
    assert.ok(entry, 'template lacks permission ' + name);
    return Object.fromEntries(entry.instance.param.map(p => [p.key, p.value]));
  }
  function eventDataAllowed(key) {
    const scope = permission('read_event_data');
    assert.ok(scope.eventDataAccess.string === 'any' ||
      scope.keyPatterns.listItem.some(p => p.string === key), 'read_event_data denied ' + key);
  }
  const calls = [], logs = [], consoleLogs = [];
  let success = 0, failure = 0, completeVendor;
  let now = 1000;
  const event = options.event || { event_name: 'generate_lead', value: 42, email: 'private@example.test' };
  const headers = {
    'x-wascer-log': '1', 'x-wascer-trace-id': traceId,
    'trace-id': 'gtm-trace-1',
    'x-container-identifier': 'container-1', 'x-user-id': 'owner 1',
    ...options.headers
  };
  const data = {
    type: 'add', spreadsheetName: 'GTM Events - My Site', sheetName: 'Leads', rows: 'A1:Z1',
    useOptimisticScenario: false, logType: 'no',
    dataList: [{ value: 'private@example.test' }, { value: 'Maria' }],
    ...options.data,
    gtmOnSuccess() { success++; }, gtmOnFailure() { failure++; }
  };
  // Accepts both documented forms: (url, options, body) -> promise (the collector copy)
  // and the legacy (url, callback, options, body) the tag uses for the proxy request.
  // A network failure of the legacy form is modeled as the callback called with
  // undefined status, headers and body.
  function sendHttpRequest(url, second, third, fourth) {
    const legacy = typeof second === 'function';
    const httpOptions = legacy ? third : second;
    const body = legacy ? fourth : third;
    const scope = permission('send_http');
    assert.ok(scope.allowedUrls.string === 'any' ||
      scope.urls.listItem.some(p => urlAllowed(p.string, url)), 'send_http denied ' + url);
    calls.push({ api: legacy ? 'callback' : 'promise', url, options: structuredClone(httpOptions), body }); // clone: objetos do vm têm outro prototype
    if (url === endpoint) {
      assert.ok(!legacy, 'collector uses the promise API');
      logs.push(JSON.parse(body));
      if (options.collectorMode === 'throw') throw new Error('collector synchronous error');
      if (options.collectorMode === 'pending') return new Promise(() => {});
      if (options.collectorMode === 'reject') return Promise.reject({ reason: 'failed' });
      return Promise.resolve({ statusCode: 202, body: '' });
    }
    const response = () => ({
      statusCode: options.status === undefined ? 200 : options.status,
      body: options.responseBody === undefined ? '{"ok":true}\n' : options.responseBody,
      headers: { authorization: 'response-credential-never-copy' }
    });
    if (legacy) {
      completeVendor = () => {
        now += 37;
        if (options.vendorError) return second(undefined, undefined, undefined);
        const res = response();
        second(res.statusCode, res.headers, res.body);
      };
      if (!options.vendorPending) Promise.resolve().then(completeVendor);
      return undefined;
    }
    return new Promise((resolve, reject) => {
      completeVendor = () => {
        now += 37;
        if (options.vendorError) reject(options.vendorError);
        else resolve(response());
      };
      if (!options.vendorPending) completeVendor();
    });
  }
  const apis = {
    JSON: safeJSON,
    Promise: { create: fn => new Promise(fn), all: Promise.all.bind(Promise) },
    sendHttpRequest,
    getRequestHeader(key) {
      const scope = permission('read_request');
      assert.ok(scope.headerAccess.string === 'any' ||
        scope.headerWhitelist.listItem.some(p => p.mapValue.some(v => v.string === key)),
        'read_request denied ' + key);
      return headers[key];
    },
    getEventData(key) { eventDataAllowed(key); return event[key]; },
    getTimestampMillis: () => now,
    getType: value => value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value,
    getContainerVersion: () => ({ debugMode: false, previewMode: false }),
    encodeUriComponent: encodeURIComponent,
    logToConsole: (...args) => consoleLogs.push(args)
  };
  const context = vm.createContext({
    data,
    require(name) { assert.ok(name in apis, 'unexpected sandbox API: ' + name); return apis[name]; }
  });
  const code = options.code === undefined ? template.code : options.code;
  new vm.Script('(function(){\n' + code + '\n})()').runInContext(context, { timeout: 1000 });
  return {
    calls, logs, consoleLogs, data, info: template.info, parameters: template.parameters,
    permissions, permission,
    get success() { return success; }, get failure() { return failure; },
    completeVendor: () => completeVendor(),
    async settle() { for (let i = 0; i < 20; i++) await Promise.resolve(); }
  };
}

module.exports = { setup, readTemplate, endpoint, proxyUrl, traceId };
