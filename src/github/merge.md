Checks if merging branch is building, checks if master is building, attempts to merge the pr, watches for builds to finish, then runs the jira move command with the in QA options
TODO (currently being worked on):
Will check if the branch is ready to merge, if it is it will proceed, if it’s not, it will attempt to merge master into the branch, then proceed

`./merge.sh ${branch_name} ${fix_version}`

fix_version is optional. If it’s already been merged once, you don’t need it. Just if it’s the first time you’re merging for that ticket

* Ticket is extracted from the branch name (for jira movements at the end)
* By using gh cli, you don’t have to have auth tokens stored in the script. Gh cli will automatically handle that as long as you’re authed there
