FROM golang:1.24-alpine

# 安裝 kubectl 和其他必要工具
RUN apk add --no-cache curl netcat-openbsd && \
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
  chmod +x kubectl && \
  mv kubectl /usr/local/bin/

WORKDIR /app

# 複製 go.mod 和 go.sum
COPY go.mod go.sum ./

# 下載依賴
RUN go mod download

# 複製所有源代碼
COPY . .

# 更新 go.mod 並下載新的依賴
RUN go mod tidy

# 編譯測試
RUN go test -c ./test/e2e -tags=e2e -o e2e-test

CMD ["./e2e-test", "-test.v"]