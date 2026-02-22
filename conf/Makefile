# ───── Image Tags ─────
V1_TINY=unspecific/victim-v1-tiny:1.4
V1_LARGE=unspecific/victim-v1-large:1.01
V2_SMGUI=unspecific/victim-v2-smgui:1.2
V2_GUI=unspecific/victim-v2-gui:1.01
WIFI_MODULE=unspecific/fr-wifi-module:1.0

TS=$(shell date +%Y%m%d_%H%M)

# ───── Build Targets ─────

build-v1-tiny:
	docker build -f victim-v1-alpine.dockerfile -t $(V1_TINY) .

build-v1-large:
	docker build -f victim-v1-debian.dockerfile -t $(V1_LARGE) .

build-v2-gui:
	docker build -f victim-v2-debian.dockerfile -t $(V2_GUI) .

build-v2-smgui:
	docker build -f victim-v2-alpine.dockerfile -t $(V2_GUI) .

build-wifi-module:
	docker build -f wifi-module.dockerfile -t $(WIFI_MODULE) .

build-all: build-v1-tiny build-v1-large build-v2-gui build-v2-smgui build-wifi-module


# ───── Package/Export ─────

package-v1-tiny:
	docker save $(V1_TINY) | gzip > victim-v1-tiny-$(TS).tar.gz

package-v1-large:
	docker save $(V1_LARGE) | gzip > victim-v1-large-$(TS).tar.gz

package-v2-gui:
	docker save $(V2_GUI) | gzip > victim-v2-gui-$(TS).tar.gz

package-v2-smgui:
	docker save $(V2_SMGUI) | gzip > victim-v2-smgui-$(TS).tar.gz

package-wifi-module:
	docker save $(WIFI_MODULE) | gzip > fr-wifi-module-$(TS).tar.gz

package-all: package-v1-tiny package-v1-large package-v2-gui package-v2-smgui package-wifi-module


# ───── Load ─────

load-v1-tiny:
	gunzip -c victim-v1-tiny-*.tar.gz | docker load

load-v1-large:
	gunzip -c victim-v1-large-*.tar.gz | docker load

load-v2-gui:
	gunzip -c victim-v2-gui-*.tar.gz | docker load

load-v2-smgui:
	gunzip -c victim-v2-smgui-*.tar.gz | docker load

load-wifi-module:
	gunzip -c fr-wifi-module-*.tar.gz | docker load

load-all: load-v1-tiny load-v1-large load-v2-gui load-v2-smgui load-wifi-module


# ───── Push ─────

push:
	docker push $(V1_TINY)
	docker push $(V1_LARGE)
	docker push $(V2_GUI)
	docker push $(V2_SMGUI)


# ───── Clean ─────

clean:
	rm -f victim-v1-tiny-*.tar.gz victim-v1-large-*.tar.gz victim-v2-gui-*.tar.gz victim-v2-smgui-*.tar.gz fr-wifi-module-*.tar.gz
	docker image prune

clean-images:
	docker rmi -f $(V1_TINY) $(V1_LARGE) $(V2_GUI) $(V2_SMGUI) $(WIFI_MODULE) || true
	docker image prune

clean-all: clean clean-images


# ───── Status ─────

status:
	@echo "🧱 Checking Docker images:"
	@docker images | grep -E 'victim-v1-|victim-v2-|fr-wifi-module' || echo "No NFR images found."


# ───── Help ─────
help:
	@echo "🛠️  Nmap Firing Range 🫥 - Docker Image Toolkit"
	@echo
	@echo "Build Targets:"
	@echo "  make build-v1-tiny       Build Alpine-based victim image"
	@echo "  make build-v1-large      Build Debian-based victim image"
	@echo "  make build-v2-gui        Build Debian desktop GUI victim image"
	@echo "  make build-v2-smgui      Build Alpine desktop GUI victim image"
	@echo "  make build-wifi-module   Build WiFi AP + IKEv2 VPN module image"
	@echo "  make build-all           Build all images"
	@echo
	@echo "Package Targets:"
	@echo "  make package-v1-tiny     Export + gzip v1-tiny image"
	@echo "  make package-v1-large    Export + gzip v1-large image"
	@echo "  make package-v2-gui      Export + gzip v2-gui image"
	@echo "  make package-v2-smgui    Export + gzip v2-smgui image"
	@echo "  make package-wifi-module Export + gzip wifi-module image"
	@echo "  make package-all         Package all images"
	@echo
	@echo "Load Targets:"
	@echo "  make load-v1-tiny        Load v1-tiny image from .tar.gz"
	@echo "  make load-v1-large       Load v1-large image from .tar.gz"
	@echo "  make load-v2-gui         Load v2-gui image from .tar.gz"
	@echo "  make load-v2-smgui       Load v2-smgui image from .tar.gz"
	@echo "  make load-wifi-module    Load wifi-module image from .tar.gz"
	@echo "  make load-all            Load all images"
	@echo
	@echo "Push Target:"
	@echo "  make push                Push all built images to registry"
	@echo
	@echo "Cleanup Targets:"
	@echo "  make clean               Remove .tar.gz export files"
	@echo "  make clean-images        Delete local Docker images"
	@echo "  make clean-all           Run both clean and clean-images"
	@echo
	@echo "Meta:"
	@echo "  make status              Show current victim image versions"

# ───── Meta ─────

.PHONY: \
	build-* package-* load-* push \
	clean clean-images clean-all status \
	build-all package-all load-all \
	build-wifi-module package-wifi-module load-wifi-module \
	help
