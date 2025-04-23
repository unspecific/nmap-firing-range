# ───── Image Tags ─────
V1_TINY=unspecific/victim-v1-tiny:1.0
V1_LARGE=unspecific/victim-v1-large:1.0
V2_GUI=unspecific/victim-v2-gui:1.0

TS=$(shell date +%Y%m%d_%H%M)

# ───── Build Targets ─────

build-v1-tiny:
	docker build -f victim-v1-alpine.dockerfile -t $(V1_TINY) .

build-v1-large:
	docker build -f victim-v1-debian.dockerfile -t $(V1_LARGE) .

build-v2-gui:
	docker build -f victim-v2.dockerfile -t $(V2_GUI) .

build-all: build-v1-tiny build-v1-large build-v2-gui


# ───── Package/Export ─────

package-v1-tiny:
	docker save $(V1_TINY) | gzip > victim-v1-tiny-$(TS).tar.gz

package-v1-large:
	docker save $(V1_LARGE) | gzip > victim-v1-large-$(TS).tar.gz

package-v2-gui:
	docker save $(V2_GUI) | gzip > victim-v2-gui-$(TS).tar.gz

package-all: package-v1-tiny package-v1-large package-v2-gui


# ───── Load ─────

load-v1-tiny:
	gunzip -c victim-v1-tiny-*.tar.gz | docker load

load-v1-large:
	gunzip -c victim-v1-large-*.tar.gz | docker load

load-v2-gui:
	gunzip -c victim-v2-gui-*.tar.gz | docker load

load-all: load-v1-tiny load-v1-large load-v2-gui


# ───── Push ─────

push:
	docker push $(V1_TINY)
	docker push $(V1_LARGE)
	docker push $(V2_GUI)


# ───── Clean ─────

clean:
	rm -f victim-v1-tiny-*.tar.gz victim-v1-large-*.tar.gz victim-v2-gui-*.tar.gz

clean-images:
	docker rmi -f $(V1_TINY) $(V1_LARGE) $(V2_GUI) || true

clean-all: clean clean-images


# ───── Status ─────

status:
	@echo "🧱 Checking Docker images:"
	@docker images | grep -E 'victim-v1-|victim-v2-' || echo "No victim images found."


# ───── Meta ─────

.PHONY: \
	build-* package-* load-* push \
	clean clean-images clean-all status \
	build-all package-all load-all
