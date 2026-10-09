.PHONY: bootstrap check lint format build test analyze sanitize app integration performance verify
bootstrap:
	./scripts/bootstrap.sh
check:
	./scripts/check.sh
lint:
	./scripts/lint.sh
format:
	./scripts/format.sh
build:
	swift build
test:
	./scripts/test.sh
analyze:
	./scripts/analyze.sh
sanitize:
	./scripts/sanitize.sh
app:
	./scripts/build-app.sh
integration: app
	python3 scripts/integration.py
performance: app
	python3 scripts/performance.py --gate
verify:
	$(MAKE) check
	$(MAKE) sanitize
	$(MAKE) integration
