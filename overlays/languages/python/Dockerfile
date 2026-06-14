# Language overlay: Python (claude-crate:python)
# uv-managed standalone CPython, so projects aren't limited to Debian's 3.11.
# Project overlays needing Python should be `FROM claude-crate:python`.
FROM claude-crate:base

RUN curl -fsSL https://astral.sh/uv/install.sh | sh \
    && uv python install 3.12
