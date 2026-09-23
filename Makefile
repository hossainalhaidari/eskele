.PHONY: build app run stop test restore-dock package update-key clean docs docs-dev docs-build docs-stop

build:
	swift build

test:
	swift test

app:
	@Scripts/build-app.sh release

run: stop
	@APP=$$(Scripts/build-app.sh release) && open "$$APP" && echo "launched $$APP"

stop:
	@pkill -x Eskele 2>/dev/null || true

# Signed, notarised DMG. Needs SIGN_IDENTITY (and NOTARY_PROFILE or NOTARY_KEY to notarise).
# Releases are made by .github/workflows/release.yml, not by hand; this is for trying the pipeline.
package:
	@Scripts/package.sh

# One-time: the key pair Sparkle signs releases with. Writes the public half into Info.plist and
# keeps the private half in your login Keychain.
update-key:
	@Scripts/update-key.sh

# Rescue path: puts the system Dock back without launching the UI.
restore-dock:
	@swift run -c release Eskele --restore-dock

clean:
	rm -rf .build $(WEBSITE)/dist

# --- Website --------------------------------------------------------------
# The homepage and documentation: Astro + Starlight, static output in
# Website/dist. Needs Node. Nothing here touches the app build.

WEBSITE := Website
DOCS_PORT ?= 4321

# A real directory target, so npm only runs when the manifest is newer than
# what is installed.
$(WEBSITE)/node_modules: $(WEBSITE)/package.json
	@npm --prefix $(WEBSITE) install
	@touch $@

# Build the static site and serve it, exactly as it will be deployed.
# astro preview daemonises, so this hands the prompt back with the server up.
docs: docs-build
	@npm --prefix $(WEBSITE) run preview -- --port $(DOCS_PORT) --open
	@echo "serving http://localhost:$(DOCS_PORT)/ - stop it with: make docs-stop"

docs-stop:
	@npm --prefix $(WEBSITE) run preview:stop 2>/dev/null || true

# Hot-reloading server, for editing the site itself. Blocks; ^C to stop.
docs-dev: $(WEBSITE)/node_modules
	@npm --prefix $(WEBSITE) run dev -- --open

# Static build only. Website/dist is then ready to upload anywhere.
docs-build: $(WEBSITE)/node_modules
	@npm --prefix $(WEBSITE) run build
