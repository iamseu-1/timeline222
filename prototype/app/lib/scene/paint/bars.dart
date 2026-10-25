import '../tile.dart';
import 'context.dart';

// 2단계의 긴 기간 막대(사건 구역의 bar 비트로 그리던 굵은 막대와 막대 안 이름)는 3단계에서
// 기간 막대 칸(구역 33~36 · paint/rails.dart)으로 갈음했다 — 같은 사건이 두 번 그려지지 않게 이 층은 비워 둔다.
//
// 층 자체는 남긴다: painter.dart의 층 차례(공용 파일)와 선택 판정(hit_test.dart의 barIndices · barInset · barHeight)이
// 아직 이 자리를 쓴다. 선택 판정을 기간 막대 칸에 맞추는 일은 그 파일을 맡은 작업자의 몫이다(보고에 적었다).
class BarLayer extends TileLayer {
  @override
  void paintTile(PaintContext c, Tile t) {}
}
