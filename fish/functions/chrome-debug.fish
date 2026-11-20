function chrome-debug --description "Launch the Chrome automation instance — DevTools port 9222 for chrome-devtools MCP"
    # Separate-instance Chrome (own data dir) because Chrome 136+ refuses the
    # debug port on the default data dir — a mere second profile can't carry it.
    # Real signed Chrome so MIC Conditional Access works (unsigned Chromium fails).
    # Daily browsing stays in the normal Chrome, which never exposes a debug port.
    if test (uname) = Darwin
        # -n: new instance, required when the normal Chrome is already running.
        # --no-startup-window: Chrome activates itself when it opens its first window, so -g
        # alone never kept it in the background (live test 2026-11-20, 8 of 8 launches took focus).
        # Without a window nothing is raised. The first new_page with background=true opens
        # one without taking focus. -g still tells open not to activate it.
        open -nga "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir="$HOME/.chrome-automation" --no-startup-window
    else
        google-chrome --remote-debugging-port=9222 --user-data-dir="$HOME/.chrome-automation" &
    end
end
