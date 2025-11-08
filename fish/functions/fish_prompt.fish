function fish_prompt
    set_color green
    echo -n (whoami)
    set_color normal
    echo -n " "
    set_color blue
    echo -n (pwd)
    set_color normal
    
    # Show git branch if in a git repo
    if git rev-parse --git-dir >/dev/null 2>&1
        set_color brmagenta
        echo -n " ("
        echo -n (git branch --show-current 2>/dev/null)
        
        # Check for uncommitted changes
        if not git diff-index --quiet HEAD -- 2>/dev/null
            echo -n "*"
        end
        
        echo -n ")"
        set_color normal
    end
    
    echo
    echo -n "\$ "
end