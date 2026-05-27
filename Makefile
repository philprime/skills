.DEFAULT_GOAL := help

REQUIRED_TOOLS := dprint pre-commit

# ============================================================================
# SETUP & INSTALLATION
# ============================================================================

## Initialize development tools and hooks
.PHONY: init
init:
	@if [ "$$(uname)" = "Darwin" ]; then \
		$(MAKE) init-darwin; \
	elif [ "$$(uname)" = "Linux" ]; then \
		$(MAKE) init-linux; \
	else \
		echo "Unsupported OS: $$(uname)"; \
		exit 1; \
	fi
	$(MAKE) install
	$(MAKE) skills

## Install macOS development tools from Brewfile
.PHONY: init-darwin
init-darwin:
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "Homebrew is required to install development tools on macOS."; \
		echo "Install Homebrew, then run 'make init' again."; \
		exit 1; \
	fi
	brew bundle

## Check Linux development tools
.PHONY: init-linux
init-linux: check-tools

## Check required development tools
.PHONY: check-tools
check-tools:
	@missing=""; \
	for tool in $(REQUIRED_TOOLS); do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			missing="$$missing $$tool"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "Missing required tools:$$missing"; \
		echo "Install them with your system package manager, then run 'make install'."; \
		exit 1; \
	fi

## Install pre-commit hooks
.PHONY: install
install: check-tools
	pre-commit install --install-hooks

## Install upstream skills from agents.toml
.PHONY: skills
skills:
	npx @sentry/dotagents install

# ============================================================================
# TESTING & QUALITY ASSURANCE
# ============================================================================

## Format repository files
.PHONY: format
format:
	dprint fmt

# ============================================================================
# HELP & DOCUMENTATION
# ============================================================================

## Show available commands
.PHONY: help
help:
	@echo "=============================================="
	@echo "PHILPRIME SKILLS DEVELOPMENT COMMANDS"
	@echo "=============================================="
	@echo ""
	@awk 'BEGIN { desc = ""; target = "" } \
	/^## / { desc = substr($$0, 4) } \
	/^\.PHONY: / && desc != "" { \
		target = $$2; \
		printf "\033[36m%-20s\033[0m %s\n", target, desc; \
		desc = ""; target = "" \
	}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Use 'make <command>' to run any command above."
	@echo ""
