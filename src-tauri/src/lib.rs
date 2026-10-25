// 역사 연표 — Tauri 껍데기. 웹 폴더(dist/web)를 그대로 띄우고 파일 대화상자·파일 쓰기·외부 링크 플러그인만 붙입니다.
use std::process::{Child, Command};
use std::sync::Mutex;

/// 메이커가 띄운 본 프로그램 미리보기 창(하나) — 다시 누르면 닫고 새로 띄웁니다.
#[derive(Default)]
struct PreviewChild(Mutex<Option<Child>>);

/// 메이커 미리보기(2026-10-16 감독 "미리보기 하려면 그냥 앱에서 확인하게 해. 본 프로그램" — 메이커의 '연표로 ↗'):
/// 고치던 작업본(.htpack 바이트)을 임시 폴더에 쓰고 본 프로그램(연표 앱)을 `--preview-dlc=<파일> [--preview-view=<시작 분>,<끝 분>]`으로 띄웁니다.
/// 본 프로그램은 서재를 임시로 복사해 그 위에 작업본을 얹어 엽니다(prototype/app/lib/archive_app.dart previewMode — 서재는 그대로).
/// 앞서 이 메이커가 띄운 미리보기 창은 닫습니다(따로 켠 연표 앱은 그대로). 실행 파일이 없으면 "no-exe"(메이커가 다시 고르게 함). 휴대폰은 안 됨.
#[tauri::command]
fn preview_in_app(state: tauri::State<'_, PreviewChild>, exe: String, bytes: Vec<u8>, name: String, view: Option<(f64, f64)>) -> Result<(), String> {
  if cfg!(mobile) {
    return Err("휴대폰에서는 본 프로그램 미리보기를 쓸 수 없습니다.".into());
  }
  let exe = std::path::PathBuf::from(exe);
  if !exe.is_file() {
    return Err("no-exe".into());
  }
  let dir = std::env::temp_dir().join("ht-maker-preview");
  std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
  let safe: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.') { c } else { '_' }).collect();
  let stem = if safe.is_empty() { String::from("draft") } else { safe };
  let file = dir.join(format!("{stem}.htpack"));
  std::fs::write(&file, &bytes).map_err(|e| e.to_string())?;
  let mut slot = state.0.lock().map_err(|e| e.to_string())?;
  if let Some(mut old) = slot.take() {
    let _ = old.kill(); // 이미 닫혔으면 실패 — 상관없음
    let _ = old.wait();
  }
  let mut cmd = Command::new(&exe);
  if let Some(parent) = exe.parent() {
    cmd.current_dir(parent);
  }
  cmd.arg(format!("--preview-dlc={}", file.display()));
  if let Some((a, b)) = view {
    cmd.arg(format!("--preview-view={a},{b}"));
  }
  *slot = Some(cmd.spawn().map_err(|e| e.to_string())?);
  Ok(())
}

// 안드로이드 · 아이패드(DLC 메이커 앱 — tauri android|ios build --config tauri.maker.conf.json)에서는 이 함수가 앱의 시작점입니다.
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_opener::init())
    .manage(PreviewChild::default())
    .invoke_handler(tauri::generate_handler![preview_in_app])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      // 아이패드 · 아이폰에는 기기의 뒤로 단추가 없다 — 화면 왼쪽 가장자리에서 밀면 뒤로 가게 한다(안드로이드의 뒤로 단추와 같은 history.back:
      // 연표 미리보기 → 메이커, 열린 대화상자 닫기 — js/platform.js의 trapBack).
      #[cfg(target_os = "ios")]
      {
        use tauri::Manager;
        if let Some(window) = app.get_webview_window("main") {
          let _ = window.with_webview(|webview| unsafe {
            let view = &*(webview.inner() as *mut objc2::runtime::AnyObject);
            let _: () = objc2::msg_send![view, setAllowsBackForwardNavigationGestures: true];
          });
        }
      }
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
