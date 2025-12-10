use configparser::ini::Ini;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use dirs;

/// Thread-safe configuration manager using INI format
#[derive(Clone)]
pub struct ConfigManager {
    ini: Arc<RwLock<Ini>>,
    config_path: PathBuf,
}

impl ConfigManager {
    /// Create a new ConfigManager instance
    pub fn new() -> Result<Self, String> {
        let config_path = get_config_path();
        let mut ini = Ini::new();

        // Load existing config or create default
        if config_path.exists() {
            ini.load(&config_path)
                .map_err(|e| format!("Failed to load config: {}", e))?;
        } else {
            // Create default config
            ini.set("app", "database_path", Some(get_default_db_path()));
            
            // Write default config to file
            ini.write(&config_path)
                .map_err(|e| format!("Failed to create default config: {}", e))?;
        }

        // AUTO-GENERATION: Only if port is NOT defined in config, generate a fresh random port.
        // This ensures we respect any manual override in the config file.
        // We do NOT call ini.save(), so this random port is ephemeral (memory only).
        if ini.get("app", "port").is_none() {
            #[cfg(debug_assertions)]
            let port = 8000;

            #[cfg(not(debug_assertions))]
            let port = {
                use std::collections::hash_map::RandomState;
                use std::hash::{BuildHasher, Hash, Hasher};
                
                let random_state = RandomState::new();
                let mut hasher = random_state.build_hasher();
                std::time::SystemTime::now().hash(&mut hasher);
                let random_offset = (hasher.finish() % 1000) as u16;
                8000 + random_offset
            };

            ini.set("app", "port", Some(port.to_string()));
        }

        Ok(Self {
            ini: Arc::new(RwLock::new(ini)),
            config_path,
        })
    }

    /// Get a string value from config
    pub fn get(&self, section: &str, key: &str) -> Option<String> {
        let ini = self.ini.read().unwrap();
        ini.get(section, key)
    }

    /// Set a string value in config
    pub fn set(&self, section: &str, key: &str, value: &str) -> Result<(), String> {
        let mut ini = self.ini.write().unwrap();
        ini.set(section, key, Some(value.to_string()));
        Ok(())
    }

    /// Remove a key from config
    pub fn remove(&self, section: &str, key: &str) -> Result<(), String> {
        let mut ini = self.ini.write().unwrap();
        ini.set(section, key, None);
        Ok(())
    }

    /// Save config to file
    pub fn save(&self) -> Result<(), String> {
        let ini = self.ini.read().unwrap();
        ini.write(&self.config_path)
            .map_err(|e| format!("Failed to save config: {}", e))
    }

    /// Reload config from file
    pub fn reload(&self) -> Result<(), String> {
        let mut ini = self.ini.write().unwrap();
        ini.load(&self.config_path)
            .map_err(|e| format!("Failed to reload config: {}", e))?;
        Ok(())
    }

    /// Get all sections and their key-value pairs
    pub fn get_all(&self) -> HashMap<String, HashMap<String, String>> {
        let ini = self.ini.read().unwrap();
        let mut result = HashMap::new();

        for section in ini.sections() {
            let mut section_map = HashMap::new();
            if let Some(section_data) = ini.get_map_ref().get(&section) {
                for (key, value) in section_data {
                    if let Some(val) = value {
                        section_map.insert(key.clone(), val.clone());
                    }
                }
            }
            result.insert(section, section_map);
        }

        result
    }

    // Type-safe helper methods

    /// Get a boolean value
    pub fn get_bool(&self, section: &str, key: &str, default: bool) -> bool {
        self.get(section, key)
            .and_then(|v| v.parse().ok())
            .unwrap_or(default)
    }

    /// Set a boolean value
    pub fn set_bool(&self, section: &str, key: &str, value: bool) -> Result<(), String> {
        self.set(section, key, &value.to_string())
    }

    /// Get an integer value
    pub fn get_int(&self, section: &str, key: &str, default: i64) -> i64 {
        self.get(section, key)
            .and_then(|v| v.parse().ok())
            .unwrap_or(default)
    }

    /// Set an integer value
    pub fn set_int(&self, section: &str, key: &str, value: i64) -> Result<(), String> {
        self.set(section, key, &value.to_string())
    }

    /// Get a float value
    pub fn get_float(&self, section: &str, key: &str, default: f64) -> f64 {
        self.get(section, key)
            .and_then(|v| v.parse().ok())
            .unwrap_or(default)
    }

    /// Set a float value
    pub fn set_float(&self, section: &str, key: &str, value: f64) -> Result<(), String> {
        self.set(section, key, &value.to_string())
    }

    // Convenience methods for common config values

    /// Get the database path
    pub fn get_database_path(&self) -> String {
        self.get("app", "database_path")
            .unwrap_or_else(get_default_db_path)
    }

    /// Set the database path
    pub fn set_database_path(&self, path: &str) -> Result<(), String> {
        self.set("app", "database_path", path)
    }

    /// Get the backend port (auto-generates random port if not set)
    pub fn get_port(&self) -> Result<u16, String> {
        // Port is guaranteed to be in the config (injected in new)
        // We use get_int which handles the parsing
        // Default to 8000 just in case, though the key should exist.
        Ok(self.get_int("app", "port", 8000) as u16)
    }

    /// Set the backend port
    pub fn set_port(&self, port: u16) -> Result<(), String> {
        self.set_int("app", "port", port as i64)?;
        self.save()
    }
}

/// Get the platform-specific configuration file path
pub fn get_config_path() -> PathBuf {
    let config_dir = if cfg!(target_os = "macos") {
        // macOS: ~/Library/Application Support/com.ngocphat.expense-manager/
        dirs::home_dir()
            .expect("Cannot get home directory")
            .join("Library")
            .join("Application Support")
            .join("com.ngocphat.expense-manager")
    } else if cfg!(target_os = "windows") {
        // Windows: %APPDATA%\com.ngocphat.expense-manager\
        dirs::config_dir()
            .expect("Cannot get config directory")
            .join("com.ngocphat.expense-manager")
    } else {
        // Linux: ~/.config/expense-manager/
        dirs::config_dir()
            .expect("Cannot get config directory")
            .join("expense-manager")
    };

    // Create directory if it doesn't exist
    fs::create_dir_all(&config_dir).expect("Cannot create config directory");

    // Config file name (no .ini extension on Unix systems)
    let config_file = if cfg!(target_os = "windows") {
        "config.ini"
    } else {
        "config"
    };

    config_dir.join(config_file)
}

/// Get the platform-specific default database path
pub fn get_default_db_path() -> String {
    let data_dir = if cfg!(target_os = "macos") {
        // macOS: ~/Library/Application Support/com.ngocphat.expense-manager/
        dirs::home_dir()
            .expect("Cannot get home directory")
            .join("Library")
            .join("Application Support")
            .join("com.ngocphat.expense-manager")
    } else if cfg!(target_os = "windows") {
        // Windows: %APPDATA%\com.ngocphat.expense-manager\
        dirs::data_dir()
            .expect("Cannot get data directory")
            .join("com.ngocphat.expense-manager")
    } else {
        // Linux: ~/.local/share/expense-manager/
        dirs::data_local_dir()
            .expect("Cannot get data directory")
            .join("expense-manager")
    };

    // Create directory if it doesn't exist
    fs::create_dir_all(&data_dir).expect("Cannot create data directory");

    // Return full path to expense.db
    data_dir
        .join("expense.db")
        .to_str()
        .expect("Cannot convert path to string")
        .to_string()
}

/// Get the platform-specific logs directory
pub fn get_logs_dir() -> PathBuf {
    let logs_dir = if cfg!(target_os = "macos") {
        // macOS: ~/Library/Logs/com.ngocphat.expense-manager/
        dirs::home_dir()
            .expect("Cannot get home directory")
            .join("Library")
            .join("Logs")
            .join("com.ngocphat.expense-manager")
    } else if cfg!(target_os = "windows") {
        // Windows: %LOCALAPPDATA%\com.ngocphat.expense-manager\logs\
        dirs::data_local_dir()
            .expect("Cannot get local data directory")
            .join("com.ngocphat.expense-manager")
            .join("logs")
    } else {
        // Linux: ~/.local/share/expense-manager/logs/
        dirs::data_local_dir()
            .expect("Cannot get data directory")
            .join("expense-manager")
            .join("logs")
    };

    // Create directory if it doesn't exist
    fs::create_dir_all(&logs_dir).expect("Cannot create logs directory");

    logs_dir
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_paths() {
        let config_path = get_config_path();
        assert!(config_path.to_str().unwrap().contains("expense-manager"));

        let db_path = get_default_db_path();
        assert!(db_path.contains("expense.db"));
    }

    #[test]
    fn test_config_manager() {
        let manager = ConfigManager::new().expect("Failed to create config manager");

        // Test string operations
        manager.set("test", "key1", "value1").unwrap();
        assert_eq!(manager.get("test", "key1"), Some("value1".to_string()));

        // Test bool operations
        manager.set_bool("test", "bool_key", true).unwrap();
        assert_eq!(manager.get_bool("test", "bool_key", false), true);

        // Test int operations
        manager.set_int("test", "int_key", 42).unwrap();
        assert_eq!(manager.get_int("test", "int_key", 0), 42);

        // Test float operations
        manager.set_float("test", "float_key", 3.14).unwrap();
        assert!((manager.get_float("test", "float_key", 0.0) - 3.14).abs() < 0.001);

        // Test database path
        let db_path = manager.get_database_path();
        assert!(!db_path.is_empty());
    }

    #[test]
    fn test_get_all() {
        let manager = ConfigManager::new().expect("Failed to create config manager");
        manager.set("section1", "key1", "value1").unwrap();
        manager.set("section2", "key2", "value2").unwrap();

        let all = manager.get_all();
        assert!(all.contains_key("section1"));
        assert!(all.contains_key("section2"));
    }
}
