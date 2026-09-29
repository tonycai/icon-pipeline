# icons.mk — icon pipeline targets. Include from your Makefile:  include icons.mk
# Settings live in icons/icon.env; one-off overrides: make icons ICON_ARGS="--bg-color #000000"

ICON_SCRIPT ?= scripts/build-icons.sh
ICON_CONFIG ?= icons/icon.env
ICON_ARGS   ?=
ICON_RUN     = bash $(ICON_SCRIPT) --config $(ICON_CONFIG)

.PHONY: icons icons-web icons-og icons-ios icons-android icons-check icons-preview icons-clean icons-deps

icons: ## Build every target listed in TARGETS (icons/icon.env)
	@$(ICON_RUN) $(ICON_ARGS)

icons-web: ## Only favicons, PWA icons, manifest
	@$(ICON_RUN) --targets web $(ICON_ARGS)

icons-og: ## Only the social share image (og.png)
	@$(ICON_RUN) --targets og $(ICON_ARGS)

icons-ios: ## Only the iOS AppIcon.appiconset
	@$(ICON_RUN) --targets ios $(ICON_ARGS)

icons-android: ## Only Android launcher / notification / Play Store icons
	@$(ICON_RUN) --targets android $(ICON_ARGS)

icons-check: ## Fail if any TARGETS output is missing or out of date (CI / pre-commit)
	@$(ICON_RUN) --check $(ICON_ARGS)

icons-preview: ## Preview a draft without writing outputs: make icons-preview SVG=icons/drafts/a.svg
	@$(ICON_RUN) --preview-only $(if $(SVG),--src $(SVG)) $(ICON_ARGS)

icons-clean: ## Remove generated icons (manifest, backups and real native dirs are kept)
	@$(ICON_RUN) --clean $(ICON_ARGS)

icons-deps: ## Show toolchain status and install hints
	@$(ICON_RUN) --deps
