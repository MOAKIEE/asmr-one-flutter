import '../models/common.dart';
import 'tag_catalog.dart';

/// 首页与搜索页优先展示的精选标签。
///
/// 直接按下载量取「热门标签」会把大量成人向词条排在最前面，
/// 作为首屏入口并不合适；这里手工挑一组通用性更强、
/// 适合作为浏览起点的标签，其余标签仍可从筛选面板进入。
class FeaturedTags {
  const FeaturedTags._();

  static const List<int> ids = [
    497, // ASMR
    496, // 双声道立体声/人头麦
    500, // 舔耳
    56, // 治愈
    442, // 掏耳
    4, // 亲热/甜蜜
    8, // 日常/生活
    637, // 亲吻
    220, // 姐姐
    86, // Cosplay/角色扮演
    659, // 按摩
    73, // 动画
  ];

  /// 解析成标签对象，忽略内置目录中不存在的 id。
  static List<Tag> resolve({int limit = 12}) {
    final out = <Tag>[];
    for (final id in ids) {
      if (out.length >= limit) break;
      final tag = BundledTags.byId(id);
      if (tag != null) out.add(tag);
    }
    return out;
  }
}
