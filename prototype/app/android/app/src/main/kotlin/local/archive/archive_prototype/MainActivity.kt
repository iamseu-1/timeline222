package local.archive.archive_prototype

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors

// DLC 더하기의 파일 고르기 창(계획 한 벌 P4 정한 것 #10 · 과제 10a — 새 플러그인 없이 · `flutter pub`은 오프라인):
// 앱의 `MethodChannel('ht/files')`(lib/ui/dlc_add.dart pickDlcFilesAndroid)이 `pick`을 부르면 시스템 고르기 창(ACTION_OPEN_DOCUMENT · 여러 개)을 띄우고,
// 고른 파일을 앱 캐시 폴더 `dlc-in/`에 복사해 `{"paths":[경로…], "skipped":[거른 파일 이름…]}`을 돌려준다 — 엔진(SQLite · 팩 읽기)은 진짜 파일 경로가
// 있어야 읽는다(content:// 주소는 못 연다). 취소하면 빈 목록. 캐시 폴더는 다음 고르기에서 비운다(넣은 뒤 원본은 저장소 안과 저장소 옆 DLC 폴더에 있다).
// 복사는 화면 줄을 막지 않게 따로 된 일꾼에서 · 결과를 돌려줄 때까지(복사 끝까지) 다음 고르기는 '이미 열림'으로 막는다.
// 다만 [STALE_MS]보다 오래 돌아오지 않은 고르기(클라우드 파일 옮기기가 멈춤 등)는 다음 `pick`에서 버린다(10a 검토 N3 — 앱은 그보다 긴 10분 뒤 기다리기를
// 멈추고 다시 고르게 한다 · lib/ui/dlc_add.dart dlcPickTimeout). 버린 고르기의 늦은 결과는 돌려주지 않는다(옮긴 파일은 다음 고르기가 지운다).
// 고르기마다 요청 번호를 따로 쓴다(10b 고침 1회차): 버린 고르기의 고르기 창이 늦게 닫혀도 그 결과가 새 고르기(`pending`)로 가지 않는다.
// 액티비티가 없어지면(다시 만들어짐 · 닫힘) 기다리던 고르기를 실패로 풀어, 엔진이 살아 있으면 앱이 10분을 기다리지 않고 다시 고르게 한다.
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingSince = 0L
    private var pendingCode = 0
    private var serial = 0
    // 고르기마다 따로 된 일꾼(멈춘 옛 복사가 새 복사를 막지 않게).
    private val copier = Executors.newCachedThreadPool()
    private val ui = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ht/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pick(result: MethodChannel.Result) {
        val old = pending
        if (old != null) {
            if (SystemClock.elapsedRealtime() - pendingSince < STALE_MS) {
                result.error("busy", "파일 고르기 창이 이미 열려 있거나 고른 파일을 옮기는 중입니다", null)
                return
            }
            // 오래 돌아오지 않은 고르기는 버린다 — 앱은 이미 기다리기를 멈췄다(늦게 답해도 앱이 버린다).
            pending = null
            reply { old.error("stale", "오래 돌아오지 않은 파일 고르기를 버렸습니다", null) }
        }
        // .htpack에는 정해진 MIME이 없어(기기마다 application/octet-stream이거나 없음) 모든 파일을 보이고 앱이 머리로 가른다.
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        serial = (serial + 1) % PICK_CODES
        val code = PICK + serial
        pending = result
        pendingSince = SystemClock.elapsedRealtime()
        pendingCode = code
        try {
            startActivityForResult(intent, code)
        } catch (e: Throwable) {
            pending = null
            result.error("no-picker", "파일 고르기 창을 열 수 없습니다: ${e.message ?: e}", null)
        }
    }

    // 결과는 한 번만 — 이미 돌려줬거나(버린 고르기) 엔진이 떠난 뒤의 답이 앱을 죽이지 않게.
    private fun reply(send: () -> Unit) {
        try {
            send()
        } catch (_: Throwable) {
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // 버린 고르기의 늦은 결과(번호가 다름)는 버린다 — 새 고르기는 제 창의 결과를 기다린다.
        if (requestCode !in PICK until PICK + PICK_CODES || requestCode != pendingCode) return
        val result = pending ?: return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pending = null
            reply { result.success(mapOf("paths" to emptyList<String>(), "skipped" to emptyList<String>())) }
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        // `pending`은 결과를 돌려줄 때 비운다 — 복사하는 동안(클라우드 파일은 몇 초) 다시 고르면 '이미 열림'으로 막혀, 둘째 복사가 캐시 폴더를 비워
        // 첫째 결과 파일을 지우는 일이 없다(8 검토 2회차 Important 2 · 앱도 고르는 동안 일을 잡아 둔다). 메모리 부족(Throwable)에도 결과는 한 번 돌려준다.
        // 그 사이 버려진 고르기(STALE_MS)면 결과를 돌려주지 않는다 — 새 고르기의 `pending`을 비우지 않는다.
        copier.execute {
            try {
                val copied = copyIn(uris)
                ui.post {
                    if (pending === result) {
                        pending = null
                        reply { result.success(copied) }
                    }
                }
            } catch (e: Throwable) {
                ui.post {
                    if (pending === result) {
                        pending = null
                        reply { result.error("copy", "고른 파일을 앱 안으로 옮기지 못했습니다: ${e.message ?: e}", null) }
                    }
                }
            }
        }
    }

    // 고른 파일들을 `cacheDir/dlc-in/<고른 때>/`에 그 이름 그대로 복사한다(이름이 겹치면 뒤에 번호 · 지난 고르기의 폴더는 지운다 — 버린 고르기의 멈춘
    // 복사와 섞이지 않게) — 앱이 이름의 확장자로 가르므로 이름을 바꾸지 않는다. 복사하기 전에 크기 · 이름을 보고 거른다(8 검토 2회차 Minor 2):
    // 팩 한도(64MB — js/packfile.js LIMITS.file)를 넘는 파일, DLC 이름(.htpack)이 아니면서 1MB를 넘는 파일, 예전 배치 파일(.htlayout — 앱이 받지 않아
    // 옮기지 않고 이름만 돌려준다 · 앱이 '예전 배치 파일' 알림을 낸다 — 계획 P4 과제 11c). 크기를 모르면 복사하다 한도를 넘을 때 멈추고 거른다.
    private fun copyIn(uris: List<Uri>): Map<String, List<String>> {
        val root = File(cacheDir, "dlc-in")
        root.listFiles()?.forEach { it.deleteRecursively() }
        val dir = File(root, SystemClock.elapsedRealtime().toString())
        if (!dir.mkdirs() && !dir.isDirectory) throw IllegalStateException("캐시 폴더를 만들 수 없습니다: $dir")
        val taken = mutableSetOf<String>()
        val paths = mutableListOf<String>()
        val skipped = mutableListOf<String>()
        uris.forEachIndexed { index, uri ->
            val (shown, size) = describe(uri)
            val base = safeName(shown ?: "dlc-${index + 1}")
            val lower = base.lowercase()
            val limit = if (lower.endsWith(".htpack")) PACK_LIMIT else OTHER_LIMIT
            if (lower.endsWith(".htlayout") || (size != null && size > limit)) {
                skipped.add(base)
                return@forEachIndexed
            }
            var name = base
            var n = 2
            while (!taken.add(name.lowercase())) name = numbered(base, n++)
            val file = File(dir, name)
            val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("$name 을(를) 열 수 없습니다")
            val whole = input.use { from -> file.outputStream().use { to -> copyAtMost(from, to, limit) } }
            if (whole) {
                paths.add(file.absolutePath)
            } else {
                file.delete()
                skipped.add(base)
            }
        }
        return mapOf("paths" to paths, "skipped" to skipped)
    }

    // [limit] 바이트까지 복사한다 — 넘으면 멈추고 거짓.
    private fun copyAtMost(from: InputStream, to: OutputStream, limit: Long): Boolean {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = from.read(buffer)
            if (read < 0) return true
            total += read
            if (total > limit) return false
            to.write(buffer, 0, read)
        }
    }

    // 표시 이름과 크기(모르면 null).
    private fun describe(uri: Uri): Pair<String?, Long?> {
        var name: String? = null
        var size: Long? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val at = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (at >= 0) cursor.getString(at)?.let { if (it.isNotBlank()) name = it }
                    val sized = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sized >= 0 && !cursor.isNull(sized)) size = cursor.getLong(sized).takeIf { it >= 0 }
                }
            }
        } catch (_: Exception) {
        }
        return Pair(name ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }, size)
    }

    // 경로 나눔표 · 금지 글자를 밑줄로(이름 하나만 남긴다).
    private fun safeName(name: String): String = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim().ifEmpty { "dlc" }

    private fun numbered(name: String, n: Int): String {
        val dot = name.lastIndexOf('.')
        return if (dot > 0) "${name.substring(0, dot)}-$n${name.substring(dot)}" else "$name-$n"
    }

    override fun onDestroy() {
        // 기다리던 고르기를 푼다 — 새 액티비티는 이 고르기의 결과를 받지 못한다(엔진이 함께 떠났으면 답은 조용히 버려진다).
        pending?.let { waiting ->
            pending = null
            reply { waiting.error("gone", "앱 화면이 다시 만들어져 파일 고르기가 멈췄습니다 — 다시 골라 주세요", null) }
        }
        copier.shutdown()
        super.onDestroy()
    }

    companion object {
        // 고르기 요청 번호의 첫 값과 개수(고를 때마다 돌려 씀 — 16비트 안).
        private const val PICK = 4917
        private const val PICK_CODES = 256

        // 이보다 오래 돌아오지 않은 고르기는 다음 `pick`에서 버린다(앱의 기다리기 한도 10분보다 짧게 — 앱이 멈춘 뒤 다시 고르면 열린다).
        private const val STALE_MS = 9L * 60 * 1000

        // 팩 파일의 한도(js/packfile.js LIMITS.file 64MB) · DLC 이름이 아닌 파일은 1MB까지만 옮겨 앱이 머리로 가른다.
        private const val PACK_LIMIT = 64L * 1024 * 1024
        private const val OTHER_LIMIT = 1L * 1024 * 1024
    }
}
