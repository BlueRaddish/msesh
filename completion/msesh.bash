# bash completion for msesh.
#
# Installed by ./install.sh, or source it yourself from ~/.bashrc:
#     source /path/to/msesh/completion/msesh.bash
#
# Every candidate list comes from `msesh complete-names KIND`, which prints one
# name per line and nothing else. Deliberately not parsed out of `msesh list`
# or `msesh preset list`: those are laid out for people to read, and the day
# someone improves that layout is the day Tab would quietly stop working — in
# two shells, since the PowerShell completer asks the same question.

_msesh_names() {
    local kind=$1
    # 2>/dev/null and no error handling anywhere: a completion that prints a
    # diagnostic into the command line is worse than one that offers nothing.
    msesh complete-names "$kind" 2>/dev/null
}

_msesh() {
    local cur prev cmd i
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}

    # The verb is the first word that is not an option or an option's value.
    cmd=
    for (( i = 1; i < COMP_CWORD; i++ )); do
        case ${COMP_WORDS[i]} in
            -s|-d|-e|-w|--session|--dir|--effort|--width|--notify|--windows)
                (( i++ )); continue ;;
            -*) continue ;;
            *)  cmd=${COMP_WORDS[i]}; break ;;
        esac
    done

    # Values, before anything else: what follows -d is a directory, not a verb.
    case $prev in
        -d|--dir)
            COMPREPLY=( $(compgen -d -- "$cur") ); return ;;
        -e|--effort)
            COMPREPLY=( $(compgen -W "low medium high xhigh ladder l m h x" -- "$cur") ); return ;;
        -w|--width|--notify)
            return ;;                   # a number; nothing useful to offer
        -s|--session)
            COMPREPLY=( $(compgen -W "$(_msesh_names sessions)" -- "$cur") ); return ;;
        --windows)
            return ;;
    esac

    if [ -z "$cmd" ]; then
        COMPREPLY=( $(compgen -W "$(_msesh_names commands)" -- "$cur") )
        return
    fi

    if [[ $cur == -* ]]; then
        local opts="-s -d -e -w -n --session --dir --effort --width --windows
                    --notify --no-notify --lazy --ephemeral --no-tab --no-trust
                    --dry-run --all"
        [ "$cmd" = send ] && opts="$opts --no-enter"
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return
    fi

    case $cmd in
        build|rebuild|add)
            # A layout, a preset or a live session — plus counts, which nobody
            # needs completed.
            COMPREPLY=( $(compgen -W "$(_msesh_names buildable)" -- "$cur") ) ;;
        attach|restore)
            COMPREPLY=( $(compgen -W "$(_msesh_names restorable) $(_msesh_names sessions)" -- "$cur") ) ;;
        kill|status|send)
            COMPREPLY=( $(compgen -W "$(_msesh_names sessions)" -- "$cur") ) ;;
        forget)
            COMPREPLY=( $(compgen -W "$(_msesh_names manifests)" -- "$cur") ) ;;
        help)
            COMPREPLY=( $(compgen -W "$(_msesh_names topics)" -- "$cur") ) ;;
        preset)
            # Sub-verb first, then a preset name for the ones that take one.
            if [ "$prev" = preset ]; then
                COMPREPLY=( $(compgen -W "list show make remove edit" -- "$cur") )
            else
                case $prev in
                    show|remove|rm|delete)
                        COMPREPLY=( $(compgen -W "$(_msesh_names presets)" -- "$cur") ) ;;
                esac
            fi ;;
        layout)
            if [ "$prev" = layout ]; then
                COMPREPLY=( $(compgen -W "list show make save remove edit" -- "$cur") )
            else
                case $prev in
                    show|remove|rm|delete|edit)
                        COMPREPLY=( $(compgen -W "$(_msesh_names layouts)" -- "$cur") ) ;;
                    save)
                        COMPREPLY=( $(compgen -W "$(_msesh_names manifests)" -- "$cur") ) ;;
                    make)
                        return ;;       # a new name: only you know it
                esac
            fi ;;
    esac
}

complete -F _msesh msesh
