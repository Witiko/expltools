FROM alpine:latest
RUN apk add --no-cache lua5.3 lua5.3-lpeg lua5.3-filesystem
RUN mkdir -p /opt/expltools/explcheck
COPY .explcheckrc /opt/expltools/
COPY explcheck/src/explcheck*.* /opt/expltools/explcheck/
COPY <<'EOF' /usr/local/bin/explcheck
#!/bin/sh
export LUA_PATH=/opt/expltools/explcheck/?.lua
lua5.3 /opt/expltools/explcheck/explcheck.lua "$@"
EOF
RUN chmod +x /usr/local/bin/explcheck
ENTRYPOINT ["explcheck"]
