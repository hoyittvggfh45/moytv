import 'dart:convert';

import 'package:moyi/app_build.dart';
import 'package:moyi/core_bridge.dart';
import 'package:moyi/local_profiles.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edition sources include DSD only in the all-source build', () async {
    SharedPreferences.setMockInitialValues({'source': 'huangdou'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(appSlug, allSourcesEnabled ? 'quanjushijie' : 'duanjushijie');
    expect(store.sources.length, allSourcesEnabled ? 8 : 1);
    expect(
      SourceSite.values.any((source) => source.id == 'dsd'),
      allSourcesEnabled,
    );
    expect(SourceSite.isAvailable('dsd'), allSourcesEnabled);
    expect(SourceSite.isKnown('dsd'), isTrue);
    expect(SourceSite.byId('dsd').name, '帝果');
    // 源门禁已整体删除（2026-11-27 用户令）：allowsSource 不再查
    // 版本可用性，恒放行；isAvailable 的版本口径保留不动。
    expect(store.allowsSource('dsd'), isTrue);
    expect(store.source, allSourcesEnabled ? 'huangdou' : 'hongguo');
    store.dispose();
  });


  test(
    'a restored foreign-source profile keeps its identity and permissions',
    () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '已有用户',
            sources: ['huangdou'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'huangdou',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(store.profile.id, 'viewer');
      expect(store.profile.admin, isFalse);
      expect(store.profile.sources, ['huangdou']);
      // 门禁已删（2026-11-27 用户令）：档案数据（身份/sources/
      // download 标志）原样保留，但不再产生拦截效果——canDownload
      // 不再被 download:false 挡，allowsSource 对任何源恒放行。
      expect(store.canDownload, isTrue);
      // source 是「首页默认选中源」的展示回退（存量逻辑）：存的源
      // 不在可见列表时落第一个可见源，与访问门禁无关。
      expect(store.source, allSourcesEnabled ? 'huangdou' : 'hongguo');
      expect(store.allowsSource('hongguo'), isTrue);
      expect(store.allowsSource('huangdou'), isTrue);
      store.dispose();
    },
  );

  test('restored DSD profile data follows edition availability', () async {
    SharedPreferences.setMockInitialValues({
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '帝果旧用户',
          sources: ['dsd'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
      'profile.viewer.source': 'dsd',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.configurationError, isNull);
    expect(store.profile.sources, ['dsd']);
    // 门禁已删（2026-11-27 用户令）：store.sources 不再按档案
    // sources 过滤，回到「全部已登记站源」；显示与否由 hiddenSites
    // 展示偏好决定，与档案数据脱钩。
    expect(
      store.sources.map((source) => source.id),
      SourceSite.values.map((source) => source.id),
    );
    expect(store.source, allSourcesEnabled ? 'dsd' : 'hongguo');
    expect(store.allowsSource('dsd'), isTrue);
    store.dispose();
  });

  test(
    'background requests no longer reject sources before native I/O',
    () async {
      // 源门禁已整体删除（2026-11-27 用户令）：后台请求不再在
      // Dart 侧按 source 准入预检抛错；请求照常下到本地核心，
      // 成败只由核心与数据本身决定（测试环境无核心，落到核心
      // 加载失败——只要不是门禁文案即可）。
      const gateMessages = {
        '当前版本不包含此站源',
        '当前用户没有此操作权限',
        '当前用户仅支持在线观看',
      };
      final repository = NativeRepository(background: true);
      final sources = [
        ...SourceSite.allValues
            .where((source) => !SourceSite.isAvailable(source.id))
            .map((source) => source.id),
        'unknown',
      ];
      for (final source in sources) {
        final drama = Drama(id: '$source:123', source: source, title: '合成数据');
        final episode = Episode({'id': '1'}, 1);
        for (final request in [
          () => repository.catalog(source),
          () => repository.cached(source),
          () => repository.sourceStatus(source),
          () => repository.startSourceJob(source, 'update'),
          () => repository.cancelSourceJob(source),
          () => repository.detail(drama),
          () => repository.cover(drama),
          () => repository.resolve(drama, episode),
          () => repository.resolveOnline(drama, episode),
          () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [
            episode,
          ]),
          () => repository.localPlayback(drama, episode),
        ]) {
          await expectLater(
            request(),
            throwsA(
              predicate(
                (Object error) =>
                    error is! AppFailure ||
                    !gateMessages.contains(error.message),
                '不是门禁拦截错误',
              ),
            ),
          );
        }
      }
    },
  );
}
