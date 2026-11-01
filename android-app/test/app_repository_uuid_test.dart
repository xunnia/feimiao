// 行级 uuid：账单、账本等新行的编号。导出再导入、导到 iOS 都按它认同一笔，
// 所以不能重复。不带种子的 Random() 种子只有 32 位，最多约 43 亿种编号，
// 30 万个里几乎必然撞上（全无重复的概率约十万分之三）；安全随机数 128 位，
// 这个数量下重复的概率可以忽略。
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/data/app_repository.dart';

void main() {
  test('row uuids stay 32 lowercase hex and do not repeat at scale', () {
    final ids = List.generate(300000, (_) => AppRepository.newRowUuidForTest());
    final format = RegExp(r'^[0-9a-f]{32}$');
    expect(ids.every(format.hasMatch), isTrue, reason: '格式要和旧编号一致');
    expect(ids.toSet().length, ids.length, reason: '30 万个编号不能有重复');
  });
}
