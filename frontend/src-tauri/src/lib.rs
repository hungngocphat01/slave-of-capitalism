// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/

mod config;
mod backend_process;

use config::{ConfigManager, get_config_path, get_default_db_path};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tauri::{Manager, State};

// Global backend process state
struct AppState {
    backend: Mutex<Option<backend_process::BackendProcess>>,
    config: Arc<Mutex<ConfigManager>>,
}

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

// Config management commands

#[tauri::command]
fn get_config_value(
    state: State<'_, AppState>,
    section: String,
    key: String,
) -> Result<Option<String>, String> {
    let config = state.config.lock().unwrap();
    Ok(config.get(&section, &key))
}

#[tauri::command]
fn set_config_value(
    state: State<'_, AppState>,
    section: String,
    key: String,
    value: String,
) -> Result<(), String> {
    let config = state.config.lock().unwrap();
    config.set(&section, &key, &value)?;
    config.save()?;
    Ok(())
}

#[tauri::command]
fn remove_config_value(
    state: State<'_, AppState>,
    section: String,
    key: String,
) -> Result<(), String> {
    let config = state.config.lock().unwrap();
    config.remove(&section, &key)?;
    config.save()?;
    Ok(())
}

#[tauri::command]
fn get_all_config(
    state: State<'_, AppState>,
) -> Result<HashMap<String, HashMap<String, String>>, String> {
    let config = state.config.lock().unwrap();
    Ok(config.get_all())
}

// Legacy compatibility commands

#[tauri::command]
fn get_config_file_path() -> Result<String, String> {
    let path = get_config_path();
    path.to_str()
        .ok_or("Failed to convert path to string".to_string())
        .map(|s| s.to_string())
}

#[tauri::command]
fn get_database_path(state: State<'_, AppState>) -> Result<String, String> {
    #[cfg(debug_assertions)]
    return Ok("(The client does not control the webserver in debug mode)".to_string());

    #[cfg(not(debug_assertions))]
    {
        let config = state.config.lock().unwrap();
        Ok(config.get_database_path())
    }
}

#[tauri::command]
async fn set_database_path(
    path: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    // Update config file
    {
        let config = state.config.lock().unwrap();
        config.set_database_path(&path)?;
        config.save()?;
    }

    // Restart backend with new database path
    restart_backend(&state, &path).await?;

    Ok(())
}

#[tauri::command]
fn get_default_database_path() -> String {
    get_default_db_path()
}

#[tauri::command]
async fn pick_database_file(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    
    let file_path = app.dialog()
        .file()
        .set_title("Select Database Location")
        .add_filter("SQLite Database", &["db", "sqlite", "sqlite3"])
        .blocking_save_file();
    
    Ok(file_path.and_then(|p| p.as_path().map(|path| path.to_string_lossy().to_string())))
}

#[tauri::command]
fn get_backend_port(state: State<'_, AppState>) -> Result<u16, String> {
    let config = state.config.lock().unwrap();
    config.get_port()
}

/// Start the backend process with the configured database path
async fn start_backend(state: &tauri::State<'_, AppState>) -> Result<(), String> {
    let (database_path, port) = {
        let config = state.config.lock().unwrap();
        let db = config.get_database_path();
        let port = config.get_port()?;
        (db, port)
    };

    let backend = backend_process::BackendProcess::start(&database_path, port).await?;

    let mut guard = state.backend.lock().unwrap();
    *guard = Some(backend);

    Ok(())
}

/// Restart the backend with a new database path
async fn restart_backend(state: &tauri::State<'_, AppState>, database_path: &str) -> Result<(), String> {
    // Stop existing backend
    {
        let mut guard = state.backend.lock().unwrap();
        *guard = None; // Drop will stop the process
    }

    // Get port from config
    let port = {
        let config = state.config.lock().unwrap();
        config.get_port()?
    };

    // Start new backend
    let backend = backend_process::BackendProcess::start(database_path, port).await?;

    let mut guard = state.backend.lock().unwrap();
    *guard = Some(backend);

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize ConfigManager
    let config_manager = ConfigManager::new()
        .expect("Failed to initialize configuration");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState {
            backend: Mutex::new(None),
            config: Arc::new(Mutex::new(config_manager)),
        })
        .setup(|app| {
            // In debug mode, assume backend is manually started
            // In production, start backend automatically
            #[cfg(not(debug_assertions))]
            {
                let app_handle = app.handle().clone();
                
                std::thread::spawn(move || {
                    tauri::async_runtime::block_on(async move {
                        let state = app_handle.state::<AppState>();
                        if let Err(e) = start_backend(&state).await {
                            eprintln!("Failed to start backend: {}", e);
                            use tauri_plugin_dialog::DialogExt;
                            use tauri_plugin_dialog::MessageDialogKind;
                            
                            app_handle.dialog()
                                .message(format!("Failed to start backend server:\n\n{}", e))
                                .title("Backend Start Error")
                                .kind(MessageDialogKind::Error)
                                .blocking_show();
                        }
                    });
                });
            }
            
            #[cfg(debug_assertions)]
            {
                eprintln!("🔧 [DEV MODE] Skipping backend auto-start");
                eprintln!("   Make sure backend is running at http://localhost:8000");
                eprintln!("   Run: cd backend && poetry run uvicorn app.main:app --reload --port 8000");
            }
            
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            get_config_value,
            set_config_value,
            remove_config_value,
            get_all_config,
            get_config_file_path,
            get_database_path,
            set_database_path,
            get_default_database_path,
            pick_database_file,
            get_backend_port,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
