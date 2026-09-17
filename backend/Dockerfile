FROM golang:1.23-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates ffmpeg tzdata && adduser -D -u 10001 app
USER app
WORKDIR /app
COPY --from=build /out/server /app/server
ENV TOVIDEO_GEOIP_DB_PATH=/app/internal/geoip/data/user-country.mmdb
EXPOSE 8080
ENV TOVIDEO_HTTP_ADDR=:8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["/app/server"]
