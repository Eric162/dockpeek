.PHONY: bootstrap check lint format build test analyze sanitize app
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
