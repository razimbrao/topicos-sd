# Estagio 1: compila um binario estatico
FROM docker.io/library/golang:1.22-alpine AS build
WORKDIR /src
# Dependencias vendorizadas em app/vendor: o build nao acessa proxy.golang.org.
COPY go.mod go.sum ./
COPY vendor ./vendor
COPY main.go ./
RUN CGO_ENABLED=0 GOFLAGS=-mod=vendor go build -trimpath -ldflags="-s -w" -o /out/api .

# Estagio 2: imagem final so com o binario (~6 MB), sem shell, usuario nao-root
FROM scratch
COPY --from=build /out/api /api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/api"]
