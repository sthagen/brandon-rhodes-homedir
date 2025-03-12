# Load oh-my-zsh if available
# git clone git://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh

# Quick abbreviations for very common redirections.

alias -g ,1='2>&1'
alias -g ,2='2>/dev/null'

# Don't treat * or ? or [] as special in arguments to `r` alias, so I
# can type regular expressions without having to quote them.  (But will
# I be annoyed that any filename arguments also can't use globs?)

alias r='noglob rg --line-buffered --max-columns=1000 --no-ignore-vcs --smart-case --sort path'

# Ignore special characters like "#" and ";" when running the "ci" command.

ci-helper () {
    local message="$history[$(print -P %h)]"
    message="$(echo "$message" | sed 's/ci //')"
    local length="${#message}"
    if (( length > 50 ))
    then
        echo 'Error: message has more than 50 characters             ^==='
        return 1
    fi
    if [ -d .git/refs/jj ]
    then
        jj describe -m "$message"
    else
        git ci -m "$message" .
    fi
}

alias ci='ci-helper #'

# Custom completions.

compdef s=ssh

# Activate virtual environments automatically when $PWD changes.

__compute_environment_slug () {
    local relative="${PWD#$HOME}"                  # Remove any $HOME prefix
    if [ "$relative" = "$PWD" ] ;then return 1 ;fi # Ignore dirs outside $HOME.
    if [ "$relative" = "" ] ;then return 1 ;fi     # Ignore $HOME itself.
    echo "${${relative#/}//\//-}"                  # "a/b/c" -> "a-b-c"
}
__detect_cd_and_possibly_activate_environment () {
    if [ "$PWD" = "$OPWD" ]
    then return
    fi
    OPWD="$PWD"
    local slug
    if slug="$(__compute_environment_slug)"
    then
        if [ "$slug" != "$ENV_SLUG" -a -d ~/.v/"$slug" ]
        then
            local PROMPT  # protect from "activate", "deactivate"
            if [ -n "$VIRTUAL_ENV" ]
            then
                deactivate
            elif [ -n "$CONDA_DEFAULT_ENV" ]
            then
                source deactivate
            fi
            source ~/.v/"$slug"/bin/activate ~/.v/"$slug"
            ENV_PATH="$PWD"
            ENV_SLUG="$slug"
        fi
    fi
    prompt_cwd=$PWD
    if [ -n "$ENV_SLUG" ] && [[ $PWD/ == ${ENV_PATH}/* ]]
    then
        prompt_cwd=${PWD#$ENV_PATH}  # "~/project/a/b" -> "/a/b"
        prompt_cwd=${prompt_cwd#/}   # "/a/b" -> "a/b"
        prompt_cwd=${prompt_cwd:-.}  # empty string -> "."
    else
        prompt_cwd="$(print -P '%~')"
    fi
}
,v () {
    local slug python version
    if ! slug=$(__compute_environment_slug)
    then
        echo "Error: must be in a directory beneath your home directory" >&2
        return 1
    fi
    if [ -f ".python-version" ]
    then
        uv venv ~/.v/"$slug"
    else
        if [ -z "$1" ]
        then
            pyenv versions | grep -v ' 3'
            echo
            uv python list
            return 1
        fi
        version="$1"
        mkdir -p ~/.v
        if [[ "$version" =~ '3.' ]]
        then
            uv venv --python "$@" ~/.v/"$slug"
        else
            shift
            python="$(PYENV_VERSION="$version" pyenv which python)"
            python2 ~/local/src/virtualenv/virtualenv.py -p "$python" "$@" \
                    ~/.v/"$slug"
        fi
    fi &&
    unset OPWD &&
    __detect_cd_and_possibly_activate_environment
}

# Build a pretty prompt.

if [ -z "$TERM" -o "$TERM" = "dumb" ]
then
    # Avoid "^[[?2004h" after each prompt when running inside of Emacs.
    unset zle_bracketed_paste
else
    autoload -Uz bracketed-paste-magic
    zle -N bracketed-paste bracketed-paste-magic

    autoload -Uz url-quote-magic
    zle -N self-insert url-quote-magic

    zle_highlight=(default:fg=0,bg=7,bold)

    if [ -z "$SSH_TTY" ]
    then
        PS1=$'%B%F{white}%(?.%K{green} .%K{red}%?) %(?.%F{green}.%F{red})%k\ue0b0%f '
    else
        PS1="${HOST:-${HOSTNAME}}"

        # Keep only the first component of a fully-qualified hostname.
        PS1="${PS1%%.*}"

        # TODO: make this fancier? or pop remote case out and simplify,
        # since who knows where I might be SSH'ing from, maybe no Unicode?
    fi

    RPROMPT=$'%B%(1V.%F{%1v}\ue0b2%K{%1v}%F{white} \ue0a0%2v .)%(3V.%F{white}%K{cyan} %3v .)%F{white}%K{black} %18<…<%4v '

    precmd() {
        local color rev root status_lines
        rehash
        __detect_cd_and_possibly_activate_environment
        root=$(git rev-parse --show-toplevel 2>/dev/null)

        if [ -n "$root" ]
        then
            if [ -d .git/refs/jj ]
            then
                status_lines="$(jj log -r '(remote_bookmarks()..@)-' \
                                --no-graph -T 'remote_bookmarks')"
                rev=$(echo $status_lines | grep -oP '(\w+)(?=@origin)')
                if jj log -T builtin_log_oneline -r 'remote_bookmarks()..' \
                      --no-graph | grep -qv '(empty)'
                then
                    color=red
                else
                    color=green
                fi
            elif [ -f "$root/.git/no-prompt" ]
            then
                # Too expensive to run "status" each time.
                rev=off
            else
                rev="$(GIT_OPTIONAL_LOCKS=0 git rev-parse --abbrev-ref HEAD)"
                status_lines="$(GIT_OPTIONAL_LOCKS=0 git status --porcelain)"
                status_lines=":${status_lines//
/:}"                            # delimit the lines with colons instead
                if [[ "$status_lines" =~ ':[^?][^?]' ]]
                then color=red
                elif [ "$status_lines" = ':' ]
                then color=green
                else color=yellow
                fi
            fi
        fi
        psvar=("$color" "$rev" "$ENV_SLUG" "$prompt_cwd")
    }
fi

# Automatically source ,p instead of running it in in a separate shell.

alias ,p="source ~/bin/,p"

# Moving forward by one word should land at the end of the next word,
# not at its beginning.

bindkey "\eF" emacs-forward-word
bindkey "\ef" emacs-forward-word

# An easy keyboard shortcut to edit a long complicated command in my editor.

autoload -z edit-command-line
zle -N edit-command-line
bindkey "^Xe" edit-command-line

# And forward-word and backward-word should not consider punctuation to
# be part of a word.

WORDCHARS=

# Prevent "!" characters from being special on the command line, since I
# always use Ctrl-R searching and Emacs command-line editing if I want
# to adjust and re-run a previous command.

unsetopt bang_hist

# Prevent duplicate commands from filling history.

setopt hist_ignore_dups

# Print the duration of the most recent command, to avoid my habit of
# Control-C'ing a command once I see that it's going to take several
# seconds, and re-running it with `time`.

,elapsed () {
    fc -l -D -1 | awk '{print "The",$3,"command took",$2,"to run"}'
}

# Don't complain if I paste part of a shell script into the command
# line, and some lines start with '#'.  They are comments!  I'm not
# trying to run the program '#'!

setopt interactivecomments

# If TAB can complete at least a partial word, then zsh by default is
# quite lazy and makes *me* hit TAB again to then see the options that
# remain following the characters it fills in. With this option, it will
# always respond to my TAB by showing the list of completions, whether
# there were a few characters that it went ahead and filled in, or not.
# I noticed this when using my new "clone" command, because typing
# "clone <TAB>" was filling in the common prefix "git@github.com:name/"
# and then making me hit TAB all over again to see the repository names.

unsetopt list_ambiguous

# Don't ring the terminal bell during completion.

setopt no_beep

# During completion, allow moving through the menu with arrow keys.

zstyle ':completion:*' menu select

# Install my other customizations.

source ~/.bashrc

# This needs to be set after ~/.bashrc and ~/.bashenv are run, because
# setting $TERMINFO_DIRS resets its value to 1.

ZLE_RPROMPT_INDENT=0
