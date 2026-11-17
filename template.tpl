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
    JSON.stringify(postBody)
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
