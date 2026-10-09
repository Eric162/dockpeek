.PHONY: check format build test app
check:
	./scripts/check.sh
format:
	./scripts/format.sh
build:
	swift build -Xswiftc -warnings-as-errors
test:
	./scripts/test.sh
app:
	./scripts/build-app.sh
