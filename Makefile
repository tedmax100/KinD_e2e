.PHONY: build run test docker-build kind-create kind-delete e2e-local clean e2e-debug kind-status kube-proxy-patch

build:
	go build -o bin/server ./cmd/server

run:
	go run ./cmd/server

test:
	go test ./...

docker-build:
	docker build -t go-e2e-app:latest .

docker-build-test:
	docker build -f test/e2e/Dockerfile -t go-e2e-test:latest .

kind-create:
	@echo "Creating single-node KinD cluster..."
	kind create cluster --name e2e-test --config ./.github/workflows/configs/kind-config.yaml --wait 300s
	$(MAKE) kube-proxy-patch

kube-proxy-patch:
	@echo "Patching kube-proxy for higher file descriptor limits..."
	kubectl -n kube-system patch daemonset kube-proxy --patch-file k8s/kube-proxy-patch.yaml || true
	kubectl -n kube-system rollout restart daemonset/kube-proxy || true
	kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=120s || true

kind-delete:
	@echo "Deleting KinD cluster..."
	kind delete cluster --name e2e-test || true

kind-status:
	@echo "=== Cluster Info ==="
	kubectl cluster-info --context kind-e2e-test || echo "Cluster not accessible"
	@echo "=== Nodes ==="
	kubectl get nodes --context kind-e2e-test -o wide || echo "No nodes found"
	@echo "=== System Pods ==="
	kubectl get pods -n kube-system --context kind-e2e-test || echo "No system pods found"
	@echo "=== Kube-proxy Status ==="
	kubectl -n kube-system get pods -l k8s-app=kube-proxy || echo "No kube-proxy pods found"

clean: kind-delete
	@echo "Cleaning up Docker images..."
	docker rmi go-e2e-app:latest go-e2e-test:latest 2>/dev/null || true
	docker system prune -f

e2e-debug: kind-status
	@echo "=== Application Pods ==="
	kubectl get pods -l app=go-e2e-app || echo "No app pods found"
	@echo "=== Services ==="
	kubectl get services || echo "No services found"
	@echo "=== Docker Containers ==="
	docker ps | grep e2e-test || echo "No KinD containers found"
	@echo "=== Docker Images ==="
	docker images | grep -E "(go-e2e|kindest)" || echo "No relevant images found"

e2e-local: clean kind-create
	@echo "Building Docker images..."
	$(MAKE) docker-build docker-build-test
	@echo "Loading images into KinD cluster..."
	kind load docker-image go-e2e-app:latest --name e2e-test
	kind load docker-image go-e2e-test:latest --name e2e-test
	@echo "Checking cluster status..."
	$(MAKE) kind-status
	@echo "Applying Kubernetes manifests..."
	kubectl apply -f k8s/ --context kind-e2e-test
	@echo "Waiting for deployment to be ready..."
	kubectl wait --for=condition=available --timeout=300s deployment/go-e2e-app
	@echo "Checking pod status..."
	kubectl get pods -l app=go-e2e-app
	@echo "Running e2e tests using Job..."
	kubectl apply -f test/k8s/e2e-job.yaml
	@echo "Waiting for e2e test job to complete..."
	kubectl wait --for=condition=complete --timeout=300s job/e2e-test || kubectl wait --for=condition=failed --timeout=10s job/e2e-test
	@echo "Getting e2e test results..."
	kubectl logs job/e2e-test
	@echo "Cleaning up test job..."
	kubectl delete -f test/k8s/e2e-job.yaml || true
	@echo "Cleaning up Kubernetes resources..."
	kubectl delete -f ./ --recursive=false || true

create-e2e-cluster:
	@echo "Creating e2e test cluster..."
	kind create cluster --name e2e-test --config kind-config.yaml
	@echo "Waiting for cluster to be ready..."
	kubectl wait --for=condition=Ready nodes --all --timeout=300s --context kind-e2e-test
	# 自动应用 kube-proxy 修复
	$(MAKE) fix-cluster-issues

# ===== 新的目标 =====
fix-cluster-issues:
	@echo "🔧 Applying cluster fixes..."
	# 等待基本 pods 启动
	sleep 15
	# 应用 kube-proxy 补丁
	kubectl patch daemonset kube-proxy -n kube-system --context kind-e2e-test --patch-file kube-proxy-patch.yaml || true
	# 重启 kube-proxy
	kubectl rollout restart daemonset/kube-proxy -n kube-system --context kind-e2e-test || true
	kubectl rollout status daemonset/kube-proxy -n kube-system --context kind-e2e-test --timeout=120s || true
	# 重启 CoreDNS
	kubectl rollout restart deployment/coredns -n kube-system --context kind-e2e-test || true
	kubectl rollout status deployment/coredns -n kube-system --context kind-e2e-test --timeout=120s || true
	@echo "Waiting for cluster to stabilize..."
	sleep 20
	kubectl get pods -n kube-system --context kind-e2e-test
	@echo "✅ Cluster fixes applied!"

verify-cluster:
	@echo "🔍 Verifying cluster health..."
	kubectl get nodes --context kind-e2e-test
	kubectl get pods -n kube-system --context kind-e2e-test
	# 测试 DNS 解析
	kubectl run test-dns --image=busybox:1.35 --rm -it --restart=Never --context kind-e2e-test -- nslookup kubernetes.default.svc.cluster.local || true