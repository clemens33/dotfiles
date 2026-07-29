# uv env from the curl installer (Linux). Brew-installed uv on macOS ships no
# env.fish and needs none — guard keeps this a no-op there.
if test -f "$HOME/.local/bin/env.fish"
    source "$HOME/.local/bin/env.fish"
end
