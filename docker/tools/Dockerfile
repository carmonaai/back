# Script host on the compose network: curl, bash and the GNU userland (awk, sed, grep) that smoke.sh, the benches
# and the scorecard drivers run, plus python3 for the load generator (standard library only; nothing is pip-installed).
# It took over the role the llama container played (the only image with curl on the network); internal endpoints have
# no gateway route, so the scripts reach them from here. Base pinned by digest; runs as a non-root user.
FROM python:3.13-slim-bookworm@sha256:a1165e272e578941b84abc79e4ab38a0305cd12803a5c4247979ac7655f4d641
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home tools
USER tools
WORKDIR /home/tools
CMD ["sleep", "infinity"]
