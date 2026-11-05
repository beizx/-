# Build stage
FROM golang:1.27-alpine AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/reader-server ./cmd/server

# Runtime stage
FROM alpine:3.20

RUN adduser -D -H app
USER app
COPY --from=build /out/reader-server /usr/local/bin/reader-server

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/healthz" || exit 1

ENTRYPOINT ["reader-server"]
