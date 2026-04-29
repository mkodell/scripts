Uses same token as ./move_ticket.sh

Params are: `./summary.sh` +
`—list` - lists all keys
`—add KEY-123` - adds a key (can be multiple at a time)
`—remove KEY-123` - removes a key (can be multiple at a time)
`—reset` - clears all keys
`—run 2026-01-09` - prints to terminal (date is start date, needed for rollovers)
`—print 2026-01-09 2026-01-21 “Sprint 30”` - prints to log

The log file can be edited to add notes (last column):
vim ./scripts/jiraSummaries/saved_summary.log
Can be aliased to ‘edit-summary’ - done in .zprofile 'alias edit-summary='vim ~/scripts/jiraSummaries/logs/$(date +%Y)-Q$(( ($(date +%-m) - 1) / 3 + 1 )).log'
Dynamically grabs the current quarter file

Notes:
* Start Date field on the ticket needs to be added to do date calculations
* Sorted by status
* Colors for keys, status
* Counts the total for regular tickets and rollovers
* https://hexdocs.pm/color_palette/color_table.html for ANSI color codes
* Output dates are formatted to mm-dd-yyyy, but input dates need to be yyyy-mm-dd for jira to read it
* Now splits to new files per quarters
* Appends newest entry to the beginning of the file, not the end (new update)
* Removes closed tickets automatically when running print (new update)
