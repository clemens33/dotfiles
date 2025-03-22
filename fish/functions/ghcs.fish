function ghcs
    # If no arguments are given, display the help text.
    if test (count $argv) -eq 0
        gh copilot suggest --help
    else
        gh copilot suggest $argv
    end
end