# vcam in PC AutoSave mode, reachable from a Docker Desktop host.
# Build on top of the vcam image (scripts/vcam): docker build -t vcam-fuji-autosave --build-arg VCAM_IMAGE=vcam-fuji .
ARG VCAM_IMAGE=vcam-fuji
FROM ${VCAM_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends iptables && rm -rf /var/lib/apt/lists/*
# The camera connects back to the client's address, which Docker Desktop shows as 192.168.65.1 and the
# container can't reach. Redirect it to the host. MODE is --discovery (send photos) or --register.
ENV MODE=--discovery
# On Linux the client's address is the bridge gateway, which works as is.
CMD ["sh", "-c", "H=$(getent ahostsv4 host.docker.internal | head -1 | cut -d' ' -f1); if [ -n \"$H\" ]; then iptables -t nat -A OUTPUT -d 192.168.65.1 -p tcp -j DNAT --to-destination $H; fi; exec stdbuf -oL build/vcam fuji_x_t20 tcp --local-ip --fs /card $MODE"]
