# Google Sheets Wascer

A Google Tag Manager **server** tag that appends or updates rows in a Google
Sheets spreadsheet from your server container. Handy for lightweight logging,
lead capture, and any report a person will open in a spreadsheet.

Built by [Wascer](https://wascer.com) for the server containers we host, and free
for anyone to use.

## What the template does

1. Appends a new row, or updates a range you point it at.
2. Targets a spreadsheet and a sheet by name.
3. Builds the row from the **Data** table, one column per entry.
4. Runs through the Wascer proxy, so you do not have to manage Google credentials in the container.
5. Optionally uses an optimistic scenario, answering before the write confirms.

## Installation

1. In your **server** container, open **Templates**, then **Tag Templates**,
   then **New**.
2. Open the three dot menu and choose **Import**.
3. Pick `template.tpl` from this repository and save.
4. Create a tag from the template, fill in the fields below, and attach a trigger.

## Fields

| Field | Type | What it does |
|---|---|---|
| Type | Radio | Whether the tag appends a row or updates an existing range. |
| Spreadsheet Name | Text | Name or id of the target spreadsheet. |
| Sheet Name | Text | Tab inside the spreadsheet. |
| Rows Range | Text | Range the tag writes to when updating. |
| Use Optimistic Scenario | Select | Answers without waiting for the write to confirm. |
| Data | Table | Values written into the row, in column order. |
| Console Logging | Radio | Controls what the tag logs to the container console. |

## Requirements

A Google Tag Manager **server** container.
Templates published by Wascer are tested against the container images we host.

## Support

Open an issue in this repository, or reach the team at
[wascer.com](https://wascer.com). If you host your server container with Wascer,
support is included in your plan.

## License

Apache License 2.0. See [LICENSE](LICENSE).
