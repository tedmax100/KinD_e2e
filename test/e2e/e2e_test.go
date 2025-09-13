//go:build e2e
// +build e2e

package e2e

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

func createKubernetesClient(t *testing.T) *kubernetes.Clientset {
	t.Helper()

	var config *rest.Config
	var err error

	// 嘗試集群內配置
	config, err = rest.InClusterConfig()
	if err != nil {
		t.Logf("Failed to get in-cluster config: %v", err)

		// 嘗試本地 kubeconfig
		kubeconfig := filepath.Join(os.Getenv("HOME"), ".kube", "config")
		if envKubeconfig := os.Getenv("KUBECONFIG"); envKubeconfig != "" {
			kubeconfig = envKubeconfig
		}

		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			t.Fatalf("Failed to create kubernetes config: %v", err)
		}
	}

	// 設置超時時間
	config.Timeout = 60 * time.Second

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		t.Fatalf("Failed to create kubernetes client: %v", err)
	}

	return clientset
}

// 簡化的 E2E 測試 - 只測試應用程式健康狀態
func TestApplicationHealth(t *testing.T) {
	// 獲取應用程式 URL
	appURL := os.Getenv("APP_URL")
	if appURL == "" {
		appURL = "http://go-e2e-app-service:8080"
	}

	// 創建 HTTP 客戶端
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	t.Logf("Testing application health at: %s", appURL)

	// 測試健康檢查端點
	maxRetries := 10
	for i := 0; i < maxRetries; i++ {
		resp, err := client.Get(appURL + "/health")
		if err != nil {
			t.Logf("Health check attempt %d failed: %v", i+1, err)
			if i < maxRetries-1 {
				time.Sleep(2 * time.Second)
				continue
			}
			t.Fatalf("Health endpoint failed after %d attempts: %v", maxRetries, err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected status 200, got %d", resp.StatusCode)
		}

		t.Logf("✅ Health check passed on attempt %d", i+1)
		t.Log("✅ E2E test completed successfully!")
		return
	}
}
