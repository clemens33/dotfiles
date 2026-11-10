function fish_prompt
    set_color green
    # $USER is set by login, su and sudo; whoami would cost one process per prompt.
    if test -n "$USER"
        echo -n $USER
    else
        echo -n (whoami)
    end
    set_color normal
    echo -n " "
    set_color blue
    echo -n (pwd)
    set_color normal

    # Git branch and dirty marker. One `git status` call answers both:
    #  - "# branch.head" is the branch ("(detached)" on a detached HEAD, which
    #    prints empty parentheses as before)
    #  - any "1", "2" or "u" record is a tracked change (staged or unstaged);
    #    untracked files are not listed (--untracked-files=no)
    #  - "# branch.oid (initial)" is a branch with no commit yet, which was
    #    always marked "*" (the old diff-index call failed there)
    # --ignore-submodules=untracked matches the old diff-index call: a modified
    # tracked file inside a submodule counts, an untracked one does not.
    # --no-optional-locks keeps the prompt from writing .git/index. LC_ALL=C pins
    # the error text matched below.
    set -l _gs (LC_ALL=C git --no-optional-locks status --porcelain=v2 --branch --untracked-files=no --no-renames --ignore-submodules=untracked 2>&1)
    set -l _rc $status
    if test $_rc -eq 0
        set -l _branch (string replace -rf '^# branch\.head (.*)$' '$1' -- $_gs)
        test "$_branch" = "(detached)"; and set _branch ""
        set_color brmagenta
        echo -n " ($_branch"
        if contains -- "# branch.oid (initial)" $_gs; or string match -qr '^[12u] ' -- $_gs
            echo -n "*"
        end
        echo -n ")"
        set_color normal
    else if not string match -q 'fatal: not a git repository*' -- $_gs[1]
        # Outside a work tree but inside git: a cwd within .git, a bare repo. status
        # refuses there, so keep the old three-call logic for these rare cases.
        # (Any unrecognised failure lands here too; the old logic then decides.)
        if git rev-parse --git-dir >/dev/null 2>&1
            set_color brmagenta
            echo -n " ("
            echo -n (git branch --show-current 2>/dev/null)
            if not git diff-index --quiet HEAD -- 2>/dev/null
                echo -n "*"
            end
            echo -n ")"
            set_color normal
        end
    end

    echo
    echo -n "\$ "
end
