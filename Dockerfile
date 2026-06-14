FROM node:22-bookworm-slim

# Base image (claude-crate:base): crate runtime essentials only — deliberately
# language-agnostic. This is the bottom of a three-tier overlay model:
#   base -> language (overlays/python, overlays/java, ...) -> project overlay.
# Overlays live in overlays/<name>/Dockerfile and chain via their FROM line;
# the wrapper resolves the chain and builds it with `--overlay <name>`.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates curl ripgrep less jq procps awscli \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l agent -d /home/agent -m node \
    && groupmod -n agent node

USER agent
ENV HOME=/home/agent
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:${PATH}"

WORKDIR /workspace
ENTRYPOINT ["claude"]
CMD ["--dangerously-skip-permissions"]
