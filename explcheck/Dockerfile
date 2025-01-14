FROM alpine:latest
RUN apk add --no-cache lua5.3 lua5.3-lpeg
RUN mkdir -p /opt/expltools/explcheck
COPY explcheck/src/explcheck*.lua /opt/expltools/explcheck/
COPY <<'EOF' /usr/local/bin/explcheck
#!/bin/sh
export LUA_PATH=/opt/expltools/explcheck/?.lua
lua5.3 /opt/expltools/explcheck/explcheck.lua "$@"
EOF
RUN chmod +x /usr/local/bin/explcheck
ENTRYPOINT ["explcheck"]
