import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/cloud/profile_sync.dart';

void main() {
  group('normalizeNickname', () {
    test('trims and keeps names up to 12 visible characters', () {
      expect(normalizeNickname('  肥喵主人  '), '肥喵主人');
      expect(normalizeNickname('一二三四五六七八九十甲乙'), '一二三四五六七八九十甲乙');
    });

    test('cuts longer names (like 20-char server names) to 12', () {
      expect(normalizeNickname('一二三四五六七八九十甲乙丙丁戊己庚辛壬癸'),
          '一二三四五六七八九十甲乙');
    });

    test('counts an emoji as one character and never splits it', () {
      const cat = '🐱';
      final twelve = List.filled(12, cat).join();
      expect(normalizeNickname('$twelve$cat'), twelve);
      expect(normalizeNickname('👨‍👩‍👧肥喵'), '👨‍👩‍👧肥喵');
    });
  });

  group('decideNicknameSync', () {
    final older = DateTime.utc(2026, 9, 1);
    final newer = DateTime.utc(2026, 9, 29);

    NicknameSyncAction decide(String local, DateTime? localAt, String? remote,
            DateTime? remoteAt) =>
        decideNicknameSync(
          local: local,
          localUpdatedAt: localAt,
          remote: remote,
          remoteUpdatedAt: remoteAt,
        );

    test('same name after normalizing does nothing', () {
      expect(decide('肥喵', newer, ' 肥喵 ', older), NicknameSyncAction.none);
      expect(decide('', null, null, null), NicknameSyncAction.none);
      expect(
        decide('一二三四五六七八九十甲乙', null, '一二三四五六七八九十甲乙丙丁', older),
        NicknameSyncAction.none,
      );
    });

    test('server has no name: upload the local one', () {
      expect(decide('肥喵', null, null, null), NicknameSyncAction.push);
      expect(decide('肥喵', older, '', newer), NicknameSyncAction.push);
    });

    test('local never set (new device or pre-sync name): take the server name',
        () {
      expect(decide('', null, '肥喵', older), NicknameSyncAction.pull);
      expect(decide('旧名字', null, '肥喵', older), NicknameSyncAction.pull);
    });

    test('newer side wins, a tie goes to the server', () {
      expect(decide('本机', newer, '服务端', older), NicknameSyncAction.push);
      expect(decide('本机', older, '服务端', newer), NicknameSyncAction.pull);
      expect(decide('本机', newer, '服务端', newer), NicknameSyncAction.pull);
      expect(decide('本机', older, '服务端', null), NicknameSyncAction.push);
    });

    test('a newer local clear neither uploads nor pulls the old name back', () {
      expect(decide('', newer, '服务端', older), NicknameSyncAction.none);
      expect(decide('', older, '服务端', newer), NicknameSyncAction.pull);
    });
  });
}
