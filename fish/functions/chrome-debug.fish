function chrome-debug --description "Launch the Chrome automation instance — DevTools port 9222 for chrome-devtools MCP"
    # Separate-instance Chrome (own data dir) because Chrome 136+ refuses the
    # debug port on the default data dir — a mere second profile can't carry it.
    # Real signed Chrome so MIC Conditional Access works (unsigned Chromium fails).
    # Daily browsing stays in the normal Chrome, which never exposes a debug port.
    if test (uname) = Darwin
        # -n: new instance — required when the normal Chrome is already running.
        open -na "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir="$HOME/.chrome-automation"
    else
        google-chrome --remote-debugging-port=9222 --user-data-dir="$HOME/.chrome-automation" &
    end
end
