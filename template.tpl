___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "displayName": "Google Sheets - Waster",
  "description": "Write data to Google Sheets via Waster proxy.",
  "containerContexts": [
    "SERVER"
  ],
  "securityGroups": []
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "RADIO",
    "name": "type",
    "displayName": "Type",
    "radioItems": [
      {
        "value": "add",
        "displayValue": "Add row"
      },
      {
        "value": "update",
        "displayValue": "Update cells"
      }
    ],
    "simpleValueType": true,
    "defaultValue": "add"
  },
  {
    "type": "TEXT",
    "name": "spreadsheetName",
    "displayName": "Spreadsheet Name",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ],
    "valueHint": "GTM Events - My Site",
    "help": "The name of the Google Sheets spreadsheet.\u003cbr/\u003e\u003cbr/\u003eIf a spreadsheet with this name already exists (created by Waster), it will be reused. Otherwise, a new spreadsheet will be created automatically.\u003cbr/\u003e\u003cbr/\u003e\u003cb\u003eNote:\u003c/b\u003e Only spreadsheets created by Waster are accessible. The Spreadsheet are divided by subfolders per container."
  },
  {
    "type": "TEXT",
    "name": "sheetName",
    "displayName": "Sheet Name",
    "simpleValueType": true,
    "help": "Enter the name of the Sheet you want to interact with.\u003cbr/\u003eIf none is specified, then it will interact with the first visible Sheet in the Spreadsheet.\u003cbr/\u003e\u003cbr/\u003eAlternatively, you can specify the Sheet Name in the \u003ci\u003eRows range\u003c/i\u003e field below using A1 Notation.",
    "valueHint": "Sheet2"
  },
  {
    "type": "TEXT",
    "name": "rows",
    "displayName": "Rows Range",
    "simpleValueType": true,
    "defaultValue": "A1:Z1",
    "help": "Specify the Rows Range using A1 Notation. You can specify the Sheet Name in the field above (preferred), or here using A1 notation.",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ]
  },
  {
    "type": "SELECT",
    "name": "useOptimisticScenario",
    "displayName": "Use Optimistic Scenario",
    "macrosInSelect": true,
    "selectItems": [
      {
        "value": true,
        "displayValue": "true"
      },
      {
        "value": false,
        "displayValue": "false"
      }
    ],
    "simpleValueType": true,
    "help": "The tag will call gtmOnSuccess() without waiting for a response from the API. This will speed up sGTM response time however your tag will always return the status fired successfully even in case it is not.",
    "defaultValue": false
  },
  {
    "type": "GROUP",
    "name": "dataListGroup",
    "displayName": "Data",
    "groupStyle": "ZIPPY_OPEN",
    "subParams": [
      {
        "type": "SIMPLE_TABLE",
        "name": "dataList",
        "displayName": "Data",
        "simpleTableColumns": [
          {
            "defaultValue": "",
            "displayName": "Cell Value",
            "name": "value",
            "type": "TEXT"
          }
        ],
        "newRowButtonText": "Add cell",
        "help": "Each line here corresponds to a cell in the Sheet. Use GTM variables to map event data."
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "logsGroup",
    "displayName": "Logs Settings",
    "groupStyle": "ZIPPY_CLOSED",
    "subParams": [
      {
        "type": "RADIO",
        "name": "logType",
        "displayName": "Console Logging",
        "radioItems": [
          {
            "value": "no",
            "displayValue": "Do not log"
          },
          {
            "value": "debug",
            "displayValue": "Log to console during debug and preview"
          },
          {
            "value": "always",
            "displayValue": "Always log to console"
          }
        ],
        "simpleValueType": true,
        "defaultValue": "debug"
      },
      {
        "type": "TEXT",
        "name": "systemLogEventType",
        "displayName": "Event type (System Log)",
        "simpleValueType": true,
        "help": "Custom System Log event type. Empty uses event_name. Collection is controlled by the container toggle."
      }
    ]
  }
]


___SANDBOXED_JS_FOR_SERVER___

const JSON = require('JSON');
const sendHttpRequest = require('sendHttpRequest');
const getContainerVersion = require('getContainerVersion');
const logToConsole = require('logToConsole');
const getRequestHeader = require('getRequestHeader');
const encodeUriComponent = require('encodeUriComponent');
const getTimestampMillis = require('getTimestampMillis');
const getEventData = require('getEventData');
const getType = require('getType');
const Promise = require('Promise');

/**********************************************************************************************/

const traceId = getRequestHeader('trace-id');
const useOptimisticScenario = isUIFieldTrue(data.useOptimisticScenario);

const sheetRange = getSheetRange();
const postBody = getData();
const postUrl = 'https://waster.sourei.com.br/google-sheets/proxy';

sendViaWasterProxy();

if (useOptimisticScenario) {
  return data.gtmOnSuccess();
}

/**********************************************************************************************/
// Range helpers

function getSheetRange() {
  var sheetName = data.sheetName ? "'" + data.sheetName + "'!" : '';
  return sheetName + data.rows;
}

/**********************************************************************************************/
// Payload builder

function getData() {
  var mappedData = [];

  if (data.dataList) {
    data.dataList.forEach(function(d) {
      mappedData.push(d.value);
    });
  }

  return {
    spreadsheetName: data.spreadsheetName,
    range: enc(sheetRange),
    type: data.type === 'add' ? 'add' : 'edit',
    values: [mappedData]
  };
}

/**********************************************************************************************/
// Request handler

function sendViaWasterProxy() {
  log({
    Name: 'GSheetsWaster',
    Type: 'Request',
    TraceId: traceId,
    EventName: data.type,
    RequestMethod: 'POST',
    RequestUrl: postUrl,
    RequestBody: postBody
  });

  var serialized = JSON.stringify(postBody);
  var started = getTimestampMillis();

  sendHttpRequest(
    postUrl,
    function(statusCode, headers, body) {
      log({
        Name: 'GSheetsWaster',
        Type: 'Response',
        TraceId: traceId,
        EventName: data.type,
        ResponseStatusCode: statusCode,
        ResponseHeaders: headers,
        ResponseBody: body
      });

      copySystemLog('google_sheets', 'Google Sheets', postUrl, 'POST', serialized, statusCode, body, started);

      if (!useOptimisticScenario) {
        if (statusCode >= 200 && statusCode < 400) {
          data.gtmOnSuccess();
        } else {
          data.gtmOnFailure();
        }
      }
    },
    {
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': enc(getRequestHeader('x-user-id')),
        'x-container-identifier': enc(getRequestHeader('x-container-identifier'))
      },
      method: 'POST'
    },
    serialized
  );
}

/**********************************************************************************************/
// Helpers

function enc(val) {
  return encodeUriComponent(val || '');
}

function isUIFieldTrue(field) {
  return [true, 'true'].indexOf(field) !== -1;
}

/**********************************************************************************************/
// Logging

function log(rawDataToLog) {
  if (determinateIsLoggingEnabled()) {
    logToConsole(JSON.stringify(rawDataToLog));
  }
}

function determinateIsLoggingEnabled() {
  var containerVersion = getContainerVersion();
  var isDebug = !!(
    containerVersion &&
    (containerVersion.debugMode || containerVersion.previewMode)
  );

  if (!data.logType) return isDebug;
  if (data.logType === 'no') return false;
  if (data.logType === 'debug') return isDebug;
  return data.logType === 'always';
}

/**********************************************************************************************/
// System Log

// System Log is controlled by the proxy header, never by tag configuration.
// Deliberately detached: neither delivery nor collector failure gates tag completion.
function copySystemLog(platform, tagName, requestUrl, requestMethod, requestBody, responseStatus, responseBody, started) {
  if (getRequestHeader('x-wascer-log') !== '1') return;
  const elapsed = getTimestampMillis() - started;
  const duration = elapsed < 0 ? 0 : elapsed > 4294967295 ? 4294967295 : elapsed;
  Promise.create((resolve) => resolve()).then(() => {
    const eventName = getEventData('event_name');
    const envelope = {
      trace_id: getRequestHeader('x-wascer-trace-id') || '',
      platform: platform,
      tag_name: tagName,
      event_name: getType(eventName) === 'string' ? eventName : '',
      event_type: data.systemLogEventType || (getType(eventName) === 'string' ? eventName : ''),
      request_method: requestMethod,
      request_url: requestUrl,
      request_body: requestBody,
      response_status: responseStatus || 0,
      response_body: getType(responseBody) === 'string' ? responseBody : '',
      duration_ms: duration
    };
    return sendHttpRequest('https://system-log.wascer.internal/log', {
      method: 'POST',
      timeout: 500,
      headers: {'Content-Type': 'application/json'}
    }, JSON.stringify(envelope));
  }).then(() => {}, () => {});
}


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "all"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://waster.sourei.com.br/*"
              },
              {
                "type": 1,
                "string": "https://system-log.wascer.internal/log"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_request",
        "versionId": "1"
      },
      "param": [
        {
          "key": "headerWhitelist",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "headerName"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "trace-id"
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "headerName"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "x-user-id"
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "headerName"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "x-container-identifier"
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "headerName"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "x-wascer-log"
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "headerName"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "x-wascer-trace-id"
                  }
                ]
              }
            ]
          }
        },
        {
          "key": "headersAllowed",
          "value": {
            "type": 8,
            "boolean": true
          }
        },
        {
          "key": "requestAccess",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "headerAccess",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "queryParameterAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_container_data",
        "versionId": "1"
      },
      "param": []
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_event_data",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keyPatterns",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "event_name"
              }
            ]
          }
        },
        {
          "key": "eventDataAccess",
          "value": {
            "type": 1,
            "string": "specific"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

Created on 24/02/2026 — v3
Google Sheets tag for GTM Server-Side (Waster platform).

Two modes:
- Add row: Appends a new row to the spreadsheet (POST :append).
- Update cells: Overwrites existing cells in the specified range (PUT).

Authentication:
- Waster Proxy: Sends the request to Waster backend which handles
  the Sheets API call on behalf of the user (x-user-id header).

Options:
- Spreadsheet Name: Name for the spreadsheet. Reuses existing if created by Waster, otherwise creates a new one (The Spreadsheet will be created inside Waster Spreadsheets folder).
- Sheet Name: Optional tab name.
- Rows Range: A1 notation range for where to write data.
- Use Optimistic Scenario: If true, gtmOnSuccess fires immediately
  without waiting for the API response.
- Data: Simple table where each row is a cell value (supports GTM variables).
- Logging: Console logging with debug/always/never modes.

System Log (manual template import; no remote publication):
Only x-wascer-log: 1 enables a best-effort output copy after the request to the
Waster proxy finishes. The copy goes only to https://system-log.wascer.internal/log
(pod loopback, trusted TLS on 443) and carries x-wascer-trace-id as trace_id.
Event type (System Log) is free text; empty uses event_name.
What is copied is the call the tag really makes: the proxy URL
(https://waster.sourei.com.br/google-sheets/proxy), the request body and the proxy
response body, as the original strings, without masking, projection or truncation.
The Google Sheets API call made by the proxy is not visible to the tag.
The proxy request keeps the callback form of sendHttpRequest, unchanged; the copy is
made inside that callback, from the status and body it receives (a missing status is
copied as 0 and a missing body as an empty string). No extra error path, headers,
credentials, config fetch, modes, queue or retry are added.
The logger is detached from tag completion; late delivery remains best-effort.
With Use Optimistic Scenario the copy is still sent when the proxy answers.
The copy itself uses the promise form of sendHttpRequest.
send_http stays a specific list, with the exact loopback URL added; the logging
destination is fixed in code and never derives from a tag field.
read_event_data is limited to event_name.
