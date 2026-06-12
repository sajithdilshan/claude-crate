FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates curl ripgrep less jq procps awscli \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l agent -d /home/agent -m node \
    && groupmod -n agent node

USER agent
ENV HOME=/home/agent
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:${PATH}"

ENV CLAUDE_CODE_USE_BEDROCK=1 \
    CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096 \
    CLAUDE_CODE_DISABLE_AUTO_MEMORY=0

WORKDIR /workspace
ENTRYPOINT ["claude"]
CMD ["--dangerously-skip-permissions"]
