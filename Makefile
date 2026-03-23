# Expense Manager - Makefile
# Build system for the desktop application

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Directories
BACKEND_DIR := backend
FRONTEND_DIR := frontend
TAURI_DIR := $(FRONTEND_DIR)/src-tauri
RESOURCES_DIR := $(TAURI_DIR)/resources/backend
BACKEND_BINARY := $(BACKEND_DIR)/dist/expense-manager-backend
APP_BUNDLE := $(TAURI_DIR)/target/release/bundle/macos/Slave of Capitalism.app

# Phony targets (not actual files)
.PHONY: all build clean dev backend frontend swiftui-verify install-deps help test

# Default target
all: build

# Help target
help:
	@echo "$(BLUE)Expense Manager Build System$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)make build$(NC)         - Build the complete application (default)"
	@echo "  $(GREEN)make dev$(NC)           - Run in development mode"
	@echo "  $(GREEN)make backend$(NC)       - Build only the backend binary"
	@echo "  $(GREEN)make frontend$(NC)      - Build only the frontend/Tauri app"
	@echo "  $(GREEN)make install-deps$(NC)  - Install all dependencies"
	@echo "  $(GREEN)make test$(NC)          - Run all tests"
	@echo "  $(GREEN)make clean$(NC)         - Clean all build artifacts"
	@echo "  $(GREEN)make help$(NC)          - Show this help message"
	@echo ""

# Install all dependencies
install-deps: install-backend-deps install-frontend-deps

install-backend-deps:
	@echo "$(BLUE)📚 Installing backend dependencies...$(NC)"
	cd $(BACKEND_DIR) && poetry install --no-root || poetry install
	@echo "$(BLUE)📦 Installing PyInstaller...$(NC)"
	cd $(BACKEND_DIR) && poetry add --group dev pyinstaller || true
	@echo "$(GREEN)✓ Backend dependencies installed$(NC)"

install-frontend-deps:
	@echo "$(BLUE)📚 Installing frontend dependencies...$(NC)"
	cd $(FRONTEND_DIR) && npm install
	@echo "$(GREEN)✓ Frontend dependencies installed$(NC)"

# Build the backend binary
backend: $(BACKEND_BINARY)

$(BACKEND_BINARY): $(BACKEND_DIR)/backend_binary.spec $(shell find $(BACKEND_DIR)/app -type f -name "*.py")
	@echo "$(BLUE)📦 Building backend binary with PyInstaller...$(NC)"
	cd $(BACKEND_DIR) && poetry run pyinstaller backend_binary.spec
	@if [ ! -f "$(BACKEND_BINARY)" ]; then \
		echo "$(RED)❌ Backend binary build failed!$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Backend binary built$(NC)"

# Copy backend to Tauri resources
$(RESOURCES_DIR)/expense-manager-backend: $(BACKEND_BINARY)
	@echo "$(BLUE)📋 Copying backend binary to Tauri resources...$(NC)"
	@mkdir -p $(RESOURCES_DIR)
	@cp $(BACKEND_BINARY) $(RESOURCES_DIR)/
	@chmod +x $(RESOURCES_DIR)/expense-manager-backend
	@echo "$(GREEN)✓ Backend binary copied$(NC)"

# Build the frontend/Tauri app (app bundle only, no DMG)
frontend: $(APP_BUNDLE)

$(APP_BUNDLE): $(RESOURCES_DIR)/expense-manager-backend
	@echo "$(BLUE)🚀 Building Tauri app (this may take 5-10 minutes)...$(NC)"
	cd $(FRONTEND_DIR) && npm run tauri build -- --bundles app
	@if [ ! -d "$(APP_BUNDLE)" ]; then \
		echo "$(RED)❌ Tauri build failed!$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Build complete!$(NC)"
	@echo ""
	@echo "$(GREEN)📱 Application location:$(NC)"
	@echo "   $(APP_BUNDLE)"
	@echo ""

# Complete build
build: frontend
	@echo "$(GREEN)✅ Complete build finished!$(NC)"
	@echo ""
	@echo "To run the app:"
	@echo "   open \"$(APP_BUNDLE)\""

# Run SwiftUI frontend verification gate
swiftui-verify:
	cd SlaveOfCapitalism && xcodegen generate
	cd SlaveOfCapitalism && xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
	cd SlaveOfCapitalism && xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# Run in development mode
dev:
	@echo "$(BLUE)🔧 Starting development mode...$(NC)"
	@echo "$(YELLOW)Note: Backend must be available via 'poetry run python -m app.main'$(NC)"
	cd $(FRONTEND_DIR) && npm run tauri dev

# Run tests
test: test-backend test-frontend

test-backend:
	@echo "$(BLUE)🧪 Running backend tests...$(NC)"
	cd $(BACKEND_DIR) && poetry run pytest -v

test-frontend:
	@echo "$(BLUE)🧪 Running frontend checks...$(NC)"
	cd $(FRONTEND_DIR) && npm run check

# Clean build artifacts
clean:
	@echo "$(BLUE)🧹 Cleaning build artifacts...$(NC)"
	@rm -rf $(BACKEND_DIR)/dist
	@rm -rf $(BACKEND_DIR)/build
	@rm -rf $(BACKEND_DIR)/*.spec.log
	@rm -rf $(RESOURCES_DIR)
	@rm -rf $(TAURI_DIR)/target
	@rm -rf $(FRONTEND_DIR)/build
	@echo "$(GREEN)✓ Clean complete$(NC)"

# Deep clean (including dependencies)
clean-all: clean
	@echo "$(BLUE)🧹 Deep cleaning (including dependencies)...$(NC)"
	@rm -rf $(BACKEND_DIR)/.venv
	@rm -rf $(FRONTEND_DIR)/node_modules
	@echo "$(GREEN)✓ Deep clean complete$(NC)"

# Quick build shortcuts
quick-backend: backend
quick-frontend: $(RESOURCES_DIR)/expense-manager-backend frontend

# Open the built app
open:
	@if [ -d "$(APP_BUNDLE)" ]; then \
		open "$(APP_BUNDLE)"; \
	else \
		echo "$(RED)❌ App not built yet. Run 'make build' first.$(NC)"; \
		exit 1; \
	fi

# Show build status
status:
	@echo "$(BLUE)📊 Build Status$(NC)"
	@echo ""
	@echo "Backend binary:"
	@if [ -f "$(BACKEND_BINARY)" ]; then \
		echo "  $(GREEN)✓$(NC) Built: $(BACKEND_BINARY)"; \
		ls -lh $(BACKEND_BINARY) | awk '{print "    Size: " $$5}'; \
	else \
		echo "  $(RED)✗$(NC) Not built"; \
	fi
	@echo ""
	@echo "Tauri resources:"
	@if [ -f "$(RESOURCES_DIR)/expense-manager-backend" ]; then \
		echo "  $(GREEN)✓$(NC) Copied to resources"; \
	else \
		echo "  $(RED)✗$(NC) Not in resources"; \
	fi
	@echo ""
	@echo "Tauri app:"
	@if [ -d "$(APP_BUNDLE)" ]; then \
		echo "  $(GREEN)✓$(NC) Built: $(APP_BUNDLE)"; \
		du -sh "$(APP_BUNDLE)" 2>/dev/null | awk '{print "    Size: " $$1}'; \
	else \
		echo "  $(RED)✗$(NC) Not built"; \
	fi
	@echo ""
