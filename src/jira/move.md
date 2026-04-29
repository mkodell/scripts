For just moving from one status to another

For code review and in progress just have to pass the ticket and status: `./move.sh KEY-685 “Code Review”`

For In QA, pass the ticket, status, label, and fix version
Example: `./move.sh KEY-685 “In QA” “ReadyForQA” v1.29.0`

Statuses (just like it’s on the board in Jira):
“In Progress”
“Code Review”
“In QA”
“Done”

* Tags and fix versions should be passed exactly like they are in Jira
* If token ever needs to be updated: https://id.atlassian.com/manage-profile/security/api-tokens
* Can now handle any number for tickets (3 numbers, 4 numbers, etc.)
