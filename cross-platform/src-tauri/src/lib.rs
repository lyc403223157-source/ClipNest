use std::{
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use enigo::{
    Direction::{Click, Press, Release},
    Enigo, Key, Keyboard, Mouse, Settings,
};
use tauri::{AppHandle, Emitter, LogicalSize, PhysicalPosition, Position, Size, Window};
use tauri_plugin_clipboard_manager::ClipboardExt;

#[tauri::command]
fn read_clipboard(app: AppHandle) -> Result<String, String> {
    app.clipboard()
        .read_text()
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn write_clipboard(app: AppHandle, text: String) -> Result<(), String> {
    app.clipboard()
        .write_text(text)
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn paste_into_previous_app(app: AppHandle, text: String) -> Result<(), String> {
    app.clipboard()
        .write_text(text)
        .map_err(|error| error.to_string())?;
    thread::sleep(Duration::from_millis(140));

    let mut enigo = Enigo::new(&Settings::default()).map_err(|error| error.to_string())?;
    #[cfg(target_os = "macos")]
    {
        enigo
            .key(Key::Meta, Press)
            .map_err(|error| error.to_string())?;
        enigo
            .key(Key::Unicode('v'), Click)
            .map_err(|error| error.to_string())?;
        enigo
            .key(Key::Meta, Release)
            .map_err(|error| error.to_string())?;
    }
    #[cfg(not(target_os = "macos"))]
    {
        enigo
            .key(Key::Control, Press)
            .map_err(|error| error.to_string())?;
        enigo
            .key(Key::Unicode('v'), Click)
            .map_err(|error| error.to_string())?;
        enigo
            .key(Key::Control, Release)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn set_picker_mode(window: Window, picker: bool) -> Result<(), String> {
    if picker {
        window
            .set_size(Size::Logical(LogicalSize::new(460.0, 400.0)))
            .map_err(|error| error.to_string())?;
        window
            .set_resizable(false)
            .map_err(|error| error.to_string())?;
        window
            .set_always_on_top(true)
            .map_err(|error| error.to_string())?;
        window
            .set_decorations(false)
            .map_err(|error| error.to_string())?;
        window
            .set_skip_taskbar(true)
            .map_err(|error| error.to_string())?;

        if let Ok(mut enigo) = Enigo::new(&Settings::default()) {
            if let Ok((cursor_x, cursor_y)) = enigo.location() {
                let x = cursor_x.saturating_sub(42);
                let y = cursor_y.saturating_add(18);
                window
                    .set_position(Position::Physical(PhysicalPosition::new(x, y)))
                    .map_err(|error| error.to_string())?;
                return Ok(());
            }
        }
    } else {
        window
            .set_size(Size::Logical(LogicalSize::new(860.0, 660.0)))
            .map_err(|error| error.to_string())?;
        window
            .set_resizable(true)
            .map_err(|error| error.to_string())?;
        window
            .set_always_on_top(false)
            .map_err(|error| error.to_string())?;
        window
            .set_decorations(true)
            .map_err(|error| error.to_string())?;
        window
            .set_skip_taskbar(false)
            .map_err(|error| error.to_string())?;
    }
    window.center().map_err(|error| error.to_string())
}

#[tauri::command]
fn open_accessibility_settings() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .spawn()
            .map_err(|error| error.to_string())?;
        return Ok(());
    }

    #[cfg(not(target_os = "macos"))]
    Err("当前系统不需要打开 macOS 辅助功能设置".into())
}

#[cfg(desktop)]
#[derive(Default)]
struct ModifierState {
    meta: bool,
    control: bool,
    shift: bool,
    alt: bool,
    captured_v: bool,
}

#[cfg(target_os = "macos")]
fn quick_picker_shortcut(state: &ModifierState) -> bool {
    state.control && !state.meta && !state.shift && !state.alt
}

#[cfg(any(target_os = "windows", target_os = "linux"))]
fn quick_picker_shortcut(state: &ModifierState) -> bool {
    state.alt && !state.meta && !state.control && !state.shift
}

#[cfg(desktop)]
fn start_keyboard_hook(app: AppHandle) {
    let state = Arc::new(Mutex::new(ModifierState::default()));
    let callback_state = Arc::clone(&state);
    let callback_app = app.clone();

    thread::Builder::new()
        .name("clipnest-keyboard-hook".into())
        .spawn(move || {
            thread::sleep(Duration::from_millis(600));
            let _ = app.emit("keyboard-hook-started", ());
            let callback = move |event: rdev::Event| -> Option<rdev::Event> {
                let Ok(mut state) = callback_state.lock() else {
                    return Some(event);
                };
                match event.event_type {
                    rdev::EventType::KeyPress(key) => match key {
                        rdev::Key::MetaLeft | rdev::Key::MetaRight => state.meta = true,
                        rdev::Key::ControlLeft | rdev::Key::ControlRight => state.control = true,
                        rdev::Key::ShiftLeft | rdev::Key::ShiftRight => state.shift = true,
                        rdev::Key::Alt | rdev::Key::AltGr => state.alt = true,
                        rdev::Key::KeyV if quick_picker_shortcut(&state) => {
                            state.captured_v = true;
                            let _ = callback_app.emit("paste-shortcut", ());
                            return None;
                        }
                        _ => {}
                    },
                    rdev::EventType::KeyRelease(key) => match key {
                        rdev::Key::MetaLeft | rdev::Key::MetaRight => state.meta = false,
                        rdev::Key::ControlLeft | rdev::Key::ControlRight => state.control = false,
                        rdev::Key::ShiftLeft | rdev::Key::ShiftRight => state.shift = false,
                        rdev::Key::Alt | rdev::Key::AltGr => state.alt = false,
                        rdev::Key::KeyV if state.captured_v => {
                            state.captured_v = false;
                            return None;
                        }
                        _ => {}
                    },
                    _ => {}
                }
                Some(event)
            };

            if let Err(error) = rdev::grab(callback) {
                let message = format!("{error:?}");
                eprintln!("ClipNest keyboard hook error: {message}");
                let _ = app.emit("keyboard-hook-error", message);
            }
        })
        .ok();
}

#[cfg(all(test, any(target_os = "windows", target_os = "linux")))]
mod tests {
    use super::*;

    #[test]
    fn alt_v_is_the_cross_platform_picker_shortcut() {
        let alt_only = ModifierState {
            alt: true,
            ..Default::default()
        };
        assert!(quick_picker_shortcut(&alt_only));
    }

    #[test]
    fn ctrl_v_remains_available_for_direct_paste() {
        let control_only = ModifierState {
            control: true,
            ..Default::default()
        };
        assert!(!quick_picker_shortcut(&control_only));
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            #[cfg(desktop)]
            start_keyboard_hook(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            read_clipboard,
            write_clipboard,
            paste_into_previous_app,
            set_picker_mode,
            open_accessibility_settings
        ])
        .run(tauri::generate_context!())
        .expect("error while running ClipNest");
}
