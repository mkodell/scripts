To get an Open Weather api key (needed for weather):
https://home.openweathermap.org/api_keys?utm_source=chatgpt.com

The file with the launch agent (which handles running in the background):
`~/Library/LaunchAgents/{plist_name}` (have to access this one through the terminal)

You want to name your plist something like 'com.{username}.dynamic_wallpaper.plist'

You can re-run the script itself if launch agent doesn’t work (fallback for single use)

To restart launch agent:
`launchctl load {plist_path}`

To see if launch agent is running:
`launchctl list | grep dynamic_wallpaper`
If the number next to this is 1, it’s failing. You want it to be 0

To kill it:
`launchctl unload {plist_path}`
