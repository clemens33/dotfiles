function claude-p --wraps claude --description "Claude Code with additional subscription (CLAUDE_CONFIG_DIR=~/.claude-p)"
    # Plain `claude` (not `env ... claude`) so a PATH shim may intercept — a
    # private overlay's ~/.local/shims/claude injects org MCP keys scoped to
    # the launched process.
    CLAUDE_CONFIG_DIR=$HOME/.claude-p claude $argv
end
