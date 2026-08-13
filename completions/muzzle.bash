_muzzle_complete() {
	local current previous commands run_options
	current="${COMP_WORDS[COMP_CWORD]}"
	previous="${COMP_WORDS[COMP_CWORD-1]:-}"
	commands="init list info run logs report loop clean doctor integrity help version"
	run_options="--verbose --dry-run --json --runner --timeout --cancel-file --policy --approve --validate-args --policy-bundle --policy-public-key --policy-signature"
	case "$previous" in
		run) COMPREPLY=( $(compgen -W "$run_options" -- "$current") ) ;;
		loop) COMPREPLY=( $(compgen -W "start next done status summary" -- "$current") ) ;;
		clean) COMPREPLY=( $(compgen -W "--dry-run --workflow --older-than --keep --json" -- "$current") ) ;;
		*) COMPREPLY=( $(compgen -W "$commands $run_options --json --help --version" -- "$current") ) ;;
	esac
}
complete -F _muzzle_complete muzzle
