FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server ./cmd/server

FROM alpine:latest
RUN apk --no-cache add ca-certificates

# 創建非 root 用戶
RUN addgroup -g 1000 appgroup && \
    adduser -D -u 1000 -G appgroup appuser

# 設定工作目錄為用戶目錄
WORKDIR /home/appuser

# 複製執行檔並設定正確的擁有者和權限
COPY --from=builder --chown=1000:1000 /app/server ./server
RUN chmod +x ./server

# 切換到非 root 用戶
USER 1000

EXPOSE 8080
CMD ["./server"]