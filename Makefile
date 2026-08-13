.PHONY: help lint format-check test benchmark quality

KUJO_BIN ?= kujo

help:
	@printf '%s\n' \
		'make lint         Check Kujo and shell sources' \
		'make format-check Check patches for whitespace errors' \
		'make test         Run the wrapper regression suite' \
		'make benchmark    Run local performance signals' \
		'make quality      Run all local quality gates'

lint:
	$(KUJO_BIN) check muzzle.kujo
	@for file in src/*.kujo; do $(KUJO_BIN) check "$$file"; done
	bash -n muzzle tests/muzzle_wrapper_regression.sh
	bash -n src/muzzle_exec.sh tests/muzzle_process_regression.sh
	bash -n tests/muzzle_install_regression.sh
	bash -n scripts/benchmark.sh scripts/install.sh scripts/sign-policy.sh completions/muzzle.bash

format-check:
	git diff --check

test:
	KUJO_BIN="$(KUJO_BIN)" bash tests/muzzle_wrapper_regression.sh
	KUJO_BIN="$(KUJO_BIN)" bash tests/muzzle_process_regression.sh
	KUJO_BIN="$(KUJO_BIN)" bash tests/muzzle_install_regression.sh

benchmark:
	KUJO_BIN="$(KUJO_BIN)" bash scripts/benchmark.sh

quality: lint format-check test
