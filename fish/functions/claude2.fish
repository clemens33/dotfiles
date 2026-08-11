function claude2 --wraps claude --description "Claude Code with second subscription (CLAUDE_CONFIG_DIR=~/.claude2)"
    # Plain `claude` (not `env ... claude`) so a PATH shim may intercept — a
    # private overlay's ~/.local/shims/claude injects org MCP keys scoped to
    # the launched process.
    CLAUDE_CONFIG_DIR=$HOME/.claude2 claude $argv
end
