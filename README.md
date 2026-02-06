These are all bash scripts

If you add `source .env &&` to the beginning of each command, it will use your env to fill variables that should be secret

For the plist, you need to manually replace those variables and then place the file in the specific location mentioned in the doc for the wallpaper script

If you want to run the scripts directly from this repo instead of moving them outside of the repo:
`chmod +x src/**/*.sh` to allow execution permissions
And add needed depenency files in a place that you can access from this repo (ex. watched_keys.txt for the jira summary script)
