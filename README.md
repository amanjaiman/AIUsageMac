# Cursor Usage Menu Bar App

A macOS menu bar app that displays your Cursor AI usage statistics directly in your menu bar.

## Features

- **Dynamic Menu Bar Icon**: Shows a donut chart that fills up based on your usage percentage
  - 🟢 Green: < 50% used
  - 🟡 Yellow: 50-70% used
  - 🟠 Orange: 70-90% used
  - 🔴 Red: > 90% used
  
- **Popover Details**: Click the icon to see:
  - Premium requests used vs. limit
  - Visual progress bar
  - Plan name
  - Usage reset date
  - Last update time

- **Auto-Refresh**: Automatically polls Cursor dashboard every 5 minutes

- **Manual Refresh**: Click the refresh button anytime

- **Quick Dashboard Access**: Open Cursor dashboard directly from the app

## Requirements

- macOS 13.0 or later
- Active Cursor subscription
- Must be logged into cursor.com in your default browser

## Installation

```bash
bash build_app.sh
cp -r CursorUsage.app /Applications/
```

Then search for "Cursor Usage" in Spotlight (Cmd+Space) to launch it.

## First-Time Setup

1. **Log in to Cursor**: Before using this app, make sure you're logged into [cursor.com](https://cursor.com) in Safari or your default browser
2. **Launch the app**: Click the donut icon in your menu bar
3. **Refresh**: If you see "Login Required", click "Open Cursor Dashboard", log in, then click refresh

## How It Works

The app uses a hidden WebKit view to load the Cursor dashboard page and parse the usage information from the rendered HTML. It shares cookies with your default browser, so if you're logged into cursor.com in Safari, the app will be able to access your usage data.

## Privacy

- The app only accesses cursor.com/dashboard
- No data is sent to any third parties
- All processing happens locally on your Mac
- Cookies are shared with Safari (via WKWebsiteDataStore.default())

## Troubleshooting

### "Login Required" message
1. Open Safari and go to https://cursor.com/dashboard
2. Log in with your Cursor account
3. Return to the menu bar app and click refresh

### Usage not updating
- Click the refresh button in the popover
- Check your internet connection
- Ensure you're still logged into cursor.com

### App not appearing in menu bar
- Check if the app is running in Activity Monitor
- Try quitting and relaunching
- Check if you have too many menu bar items (some may be hidden)

## License

MIT License - Feel free to modify and distribute!
