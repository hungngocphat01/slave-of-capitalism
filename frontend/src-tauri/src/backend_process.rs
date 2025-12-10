use std::process::{Child, Command, Stdio};
use std::time::Duration;

/// Backend process handle
pub struct BackendProcess {
    process: Option<Child>,
    port: u16,
}

impl BackendProcess {
    /// Start the backend server with the specified database path
    pub async fn start(database_path: &str, port: u16) -> Result<Self, String> {
        // Get the backend binary path
        let backend_binary = get_backend_binary_path()?;
        
        eprintln!("🚀 [BACKEND] Starting backend process...");
        eprintln!("   Binary: {} {:?}", backend_binary.0, backend_binary.1);
        eprintln!("   Database: {}", database_path);
        eprintln!("   Port: {}", port);

        // Create log files for this session
        let log_file = create_backend_log_file()?;
        eprintln!("   Log file: {:?}", log_file);

        // Start the backend process
        let mut cmd = Command::new(&backend_binary.0);
        cmd.args(&backend_binary.1);
        
        // In development mode with uvicorn, pass host and port as CLI args
        #[cfg(debug_assertions)]
        {
            cmd.arg("--host").arg("127.0.0.1");
            cmd.arg("--port").arg(port.to_string());
        }
        
        // Also set environment variables for compatibility
        cmd.env("DATABASE_PATH", database_path);
        cmd.env("PORT", port.to_string());
        
        // Redirect stdout and stderr to log file
        let log_file_stdout = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)
            .map_err(|e| format!("Failed to open log file for stdout: {}", e))?;
        
        let log_file_stderr = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)
            .map_err(|e| format!("Failed to open log file for stderr: {}", e))?;
        
        cmd.stdout(Stdio::from(log_file_stdout));
        cmd.stderr(Stdio::from(log_file_stderr));
        
        let child = cmd.spawn()
            .map_err(|e| {
                eprintln!("❌ [BACKEND] Failed to spawn process: {}", e);
                format!("Failed to start backend: {}", e)
            })?;

        eprintln!("✓ [BACKEND] Process spawned with PID: {:?}", child.id());

        let mut backend = BackendProcess {
            process: Some(child),
            port,
        };

        // Wait for backend to be ready
        eprintln!("⏳ [BACKEND] Waiting for backend to be ready...");
        if !backend.wait_for_ready(Duration::from_secs(5)).await? {
            eprintln!("❌ [BACKEND] Backend failed to start within timeout");
            backend.stop();
            return Err("Backend failed to start within timeout".to_string());
        }

        eprintln!("✅ [BACKEND] Backend is ready!");
        Ok(backend)
    }

    /// Check if backend is healthy
    async fn check_health(&self) -> bool {
        let url = format!("http://127.0.0.1:{}/api/health", self.port);
        
        match reqwest::get(&url).await {
            Ok(response) => {
                let is_ok = response.status().is_success();
                if is_ok {
                    eprintln!("✓ [BACKEND] Health check passed");
                } else {
                    eprintln!("⚠️  [BACKEND] Health check failed with status: {}", response.status());
                }
                is_ok
            }
            Err(e) => {
                eprintln!("⚠️  [BACKEND] Health check error: {}", e);
                false
            }
        }
    }

    /// Wait for backend to be ready with timeout
    async fn wait_for_ready(&mut self, timeout: Duration) -> Result<bool, String> {
        let start = std::time::Instant::now();
        let check_interval = Duration::from_millis(200);

        while start.elapsed() < timeout {
            if self.check_health().await {
                return Ok(true);
            }
            tokio::time::sleep(check_interval).await;
        }

        Ok(false)
    }

    /// Stop the backend process
    pub fn stop(&mut self) {
        if let Some(mut child) = self.process.take() {
            println!("⏹️  Stopping backend...");
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    /// Check if the process is still running
    pub fn is_running(&mut self) -> bool {
        if let Some(ref mut child) = self.process {
            match child.try_wait() {
                Ok(None) => true,  // Still running
                _ => false,         // Exited or error
            }
        } else {
            false
        }
    }
}

impl Drop for BackendProcess {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Create a new backend log file with timestamp
fn create_backend_log_file() -> Result<std::path::PathBuf, String> {
    use std::time::SystemTime;
    
    // Import get_logs_dir from config module
    use crate::config::get_logs_dir;
    
    let logs_dir = get_logs_dir();
    
    // Create timestamp for log file
    let timestamp = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map_err(|e| format!("Failed to get system time: {}", e))?
        .as_secs();
    
    let log_file = logs_dir.join(format!("backend-{}.log", timestamp));
    
    // Create the file and write header
    std::fs::write(&log_file, format!("=== Backend Log Started at {} ===\n", 
        chrono::Local::now().format("%Y-%m-%d %H:%M:%S")))
        .map_err(|e| format!("Failed to create log file: {}", e))?;
    
    Ok(log_file)
}

/// Get the path to the backend binary
/// Returns (program, args)
fn get_backend_binary_path() -> Result<(String, Vec<String>), String> {
    #[cfg(debug_assertions)]
    {
        eprintln!("🔧 [BACKEND] Using development mode (poetry + uvicorn)");
        Ok(("poetry".to_string(), vec![
            "run".to_string(),
            "uvicorn".to_string(),
            "app.main:app".to_string(),
        ]))
    }
    
    #[cfg(not(debug_assertions))]
    {
        eprintln!("📦 [BACKEND] Using production mode (bundled binary)");
        use std::env;
        
        let exe_dir = env::current_exe()
            .map_err(|e| {
                eprintln!("❌ [BACKEND] Failed to get executable path: {}", e);
                format!("Failed to get executable path: {}", e)
            })?
            .parent()
            .ok_or_else(|| {
                eprintln!("❌ [BACKEND] Failed to get parent directory");
                "Failed to get parent directory".to_string()
            })?
            .to_path_buf();
        
        eprintln!("   Executable dir: {:?}", exe_dir);
        
        let resources_dir = exe_dir
            .parent()
            .ok_or_else(|| {
                eprintln!("❌ [BACKEND] Failed to get Contents directory");
                "Failed to get Contents directory".to_string()
            })?
            .join("Resources");
        
        eprintln!("   Resources dir: {:?}", resources_dir);
        
        let binary_path = resources_dir
            .join("backend")
            .join("expense-manager-backend");
        
        eprintln!("   Looking for binary at: {:?}", binary_path);
        
        if !binary_path.exists() {
            eprintln!("❌ [BACKEND] Binary not found!");
            eprintln!("   Checked: {:?}", binary_path);
            
            // List what's actually in the resources directory
            if let Ok(entries) = std::fs::read_dir(&resources_dir) {
                eprintln!("   Contents of Resources directory:");
                for entry in entries.flatten() {
                    eprintln!("     - {:?}", entry.path());
                }
            }
            
            return Err(format!(
                "Backend binary not found at {:?}",
                binary_path
            ));
        }
        
        eprintln!("✓ [BACKEND] Binary found");
        
        // Make sure the binary is executable
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let metadata = std::fs::metadata(&binary_path)
                .map_err(|e| format!("Failed to get binary metadata: {}", e))?;
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o755);
            std::fs::set_permissions(&binary_path, permissions)
                .map_err(|e| format!("Failed to set binary permissions: {}", e))?;
            eprintln!("✓ [BACKEND] Binary permissions set to executable");
        }
        
        Ok((
            binary_path
                .to_str()
                .ok_or("Failed to convert binary path to string")?
                .to_string(),
            vec![]
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backend_binary_path() {
        let result = get_backend_binary_path();
        assert!(result.is_ok());
    }
}
