package com.historytimeline.maker

import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

// DLC 메이커 안드로이드 앱의 첫 화면 — tauri android init이 만든 것을 prototype/scripts/release/build-maker-android.sh가 이 파일로 덮어씁니다.
// 안드로이드 15부터는 앱이 상태 줄 · 탐색 줄 밑까지 그려지므로(edge-to-edge), 화면(WebView)을 그 줄들 · 화면 구멍 · 키보드 높이만큼 안으로 들여
// 메이커의 머리 줄과 입력 칸이 그 밑에 가리지 않게 합니다.
class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    val root = findViewById<View>(android.R.id.content)
    ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
      val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime())
      v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
      WindowInsetsCompat.CONSUMED
    }
  }
}
