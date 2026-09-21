import 'common.dart';

/// 排序字段（对应接口的 `order` 参数）。
enum WorkOrder {
  createDate('create_date'),
  release('release'),
  dlCount('dl_count'),
  rateAverage('rate_average_2dp'),
  reviewCount('review_count'),
  price('price'),
  id('id'),
  random('random'),
  betterRandom('betterRandom');

  const WorkOrder(this.value);
  final String value;
}

enum SortDirection {
  desc('desc'),
  asc('asc');

  const SortDirection(this.value);
  final String value;
}

/// 浏览 / 搜索用的查询条件。
///
/// 说明：接口对 `sort=asc` 时价格、时长等语义会变化，
/// 这里保持与官网一致，仅透传参数。
class WorkQuery {
  const WorkQuery({
    this.keyword,
    this.order = WorkOrder.createDate,
    this.sort = SortDirection.desc,
    this.page = 1,
    this.pageSize = 20,
    this.tags = const [],
    this.circles = const [],
    this.vas = const [],
    this.rate,
    this.duration,
    this.subtitle,
    this.includeTranslationWorks,
    this.nsfw,
  });

  final String? keyword;
  final WorkOrder order;
  final SortDirection sort;
  final int page;
  final int pageSize;

  /// 标签 id 列表，接口以逗号分隔传递。
  final List<int> tags;

  /// 社团 id 列表。
  final List<int> circles;

  /// 声优 id 列表。
  final List<String> vas;

  /// 最低评分（0~5）。
  final double? rate;

  /// 最短时长（秒）。
  final int? duration;

  /// 仅带字幕。
  final bool? subtitle;

  /// 包含翻译版本。
  final bool? includeTranslationWorks;

  /// true = 只看 18 禁；false = 只看全年龄；null = 全部。
  final bool? nsfw;

  WorkQuery copyWith({
    String? keyword,
    bool clearKeyword = false,
    WorkOrder? order,
    SortDirection? sort,
    int? page,
    int? pageSize,
    List<int>? tags,
    List<int>? circles,
    List<String>? vas,
    double? rate,
    bool clearRate = false,
    int? duration,
    bool clearDuration = false,
    bool? subtitle,
    bool? includeTranslationWorks,
    bool? nsfw,
    bool clearNsfw = false,
  }) {
    return WorkQuery(
      keyword: clearKeyword ? null : (keyword ?? this.keyword),
      order: order ?? this.order,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      tags: tags ?? this.tags,
      circles: circles ?? this.circles,
      vas: vas ?? this.vas,
      rate: clearRate ? null : (rate ?? this.rate),
      duration: clearDuration ? null : (duration ?? this.duration),
      subtitle: subtitle ?? this.subtitle,
      includeTranslationWorks:
          includeTranslationWorks ?? this.includeTranslationWorks,
      nsfw: clearNsfw ? null : (nsfw ?? this.nsfw),
    );
  }

  Map<String, dynamic> toQueryParameters() {
    final q = <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
      'order': order.value,
      'sort': sort.value,
    };
    void put(String key, Object? value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      q[key] = value is List ? value.join(',') : value;
    }

    put('keyword', keyword?.trim());
    put('tags', tags);
    put('circle', circles);
    put('vas', vas);
    put('rate', rate);
    put('duration', duration);
    if (subtitle == true) put('subtitle', 1);
    if (includeTranslationWorks == true) put('includeTranslationWorks', 1);
    if (nsfw != null) put('nsfw', nsfw! ? 'true' : 'false');
    return q;
  }

  /// 当前是否有任何生效的筛选条件（不含排序）。
  bool get hasFilters =>
      tags.isNotEmpty ||
      circles.isNotEmpty ||
      vas.isNotEmpty ||
      rate != null ||
      duration != null ||
      subtitle == true ||
      includeTranslationWorks == true ||
      nsfw != null;

  int get filterCount => [
    tags.isNotEmpty,
    circles.isNotEmpty,
    vas.isNotEmpty,
    rate != null,
    duration != null,
    subtitle == true,
    includeTranslationWorks == true,
    nsfw != null,
  ].where((e) => e).length;
}

/// 作品。列表接口与详情接口返回结构基本一致，详情多出 `tags` / `vas` 等字段。
class Work {
  const Work({
    required this.id,
    required this.title,
    required this.circleId,
    required this.circleName,
    required this.nsfw,
    required this.release,
    required this.dlCount,
    required this.price,
    required this.reviewCount,
    required this.rateCount,
    required this.rateAverage,
    this.rateCountDetail = const [],
    this.rank = const [],
    this.hasSubtitle = false,
    this.createDate = '',
    this.vas = const [],
    this.tags = const [],
    this.languageEditions = const [],
    this.ageCategory = '',
    this.duration,
    this.sourceType,
    this.sourceId,
    this.sourceUrl,
    this.circle,
    this.mainCoverUrl = '',
    this.samCoverUrl = '',
    this.thumbnailCoverUrl = '',
    this.userRating,
    this.reviewText,
  });

  final int id;
  final String title;
  final int circleId;
  final String circleName;
  final bool nsfw;
  final String release;
  final int dlCount;

  /// 日元价格，0 表示免费。
  final int price;
  final int reviewCount;
  final int rateCount;
  final double rateAverage;
  final List<RateCountDetail> rateCountDetail;
  final List<RankEntry> rank;
  final bool hasSubtitle;
  final String createDate;
  final List<Va> vas;
  final List<Tag> tags;
  final List<LanguageEdition> languageEditions;
  final String ageCategory;

  /// 作品总时长（秒）。
  final int? duration;
  final String? sourceType;
  final String? sourceId;
  final String? sourceUrl;
  final Circle? circle;
  final String mainCoverUrl;
  final String samCoverUrl;
  final String thumbnailCoverUrl;

  /// 当前登录用户对该作品的评分（未登录 / 未评分时为 null）。
  final double? userRating;
  final String? reviewText;

  bool get isFree => price == 0;

  /// DLsite 的 RJ / VJ 编号，例如 `RJ01653004`。
  String get workNo => sourceId ?? '';

  /// 是否包含中文版本（依据 work_attributes 推断的语言标记）。
  bool get hasChineseEdition =>
      languageEditions.any((e) => e.lang.toUpperCase().startsWith('CHI'));

  factory Work.fromJson(Map<String, dynamic> json) {
    final circle = json['circle'] == null
        ? null
        : Circle.fromJson(asMap(json['circle']));
    return Work(
      id: asInt(json['id']),
      title: asString(json['title']),
      circleId: asInt(json['circle_id']),
      circleName: asString(json['name']),
      nsfw: asBool(json['nsfw']),
      release: asString(json['release']),
      dlCount: asInt(json['dl_count']),
      price: asInt(json['price']),
      reviewCount: asInt(json['review_count']),
      rateCount: asInt(json['rate_count']),
      rateAverage: asDouble(json['rate_average_2dp']),
      rateCountDetail: asMapList(json['rate_count_detail'])
          .map(RateCountDetail.fromJson)
          .toList(),
      rank: asMapList(json['rank']).map(RankEntry.fromJson).toList(),
      hasSubtitle: asBool(json['has_subtitle']),
      createDate: asString(json['create_date']),
      vas: asMapList(json['vas']).map(Va.fromJson).toList(),
      tags: asMapList(json['tags']).map(Tag.fromJson).toList(),
      languageEditions: asMapList(json['language_editions'])
          .map(LanguageEdition.fromJson)
          .toList(),
      ageCategory: asString(json['age_category_string']),
      duration: asIntOrNull(json['duration']),
      sourceType: asStringOrNull(json['source_type']),
      sourceId: asStringOrNull(json['source_id']),
      sourceUrl: asStringOrNull(json['source_url']),
      circle: circle,
      mainCoverUrl: asString(json['mainCoverUrl']),
      samCoverUrl: asString(json['samCoverUrl']),
      thumbnailCoverUrl: asString(json['thumbnailCoverUrl']),
      userRating: asDoubleOrNull(json['userRating']),
      reviewText: asStringOrNull(json['review_text']),
    );
  }
}

/// 作品列表接口返回体。
class WorksPage {
  const WorksPage({
    required this.works,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<Work> works;
  final int page;
  final int pageSize;
  final int totalCount;

  int get maxPage => pageSize <= 0 ? 1 : (totalCount / pageSize).ceil();

  factory WorksPage.fromJson(Map<String, dynamic> json) {
    final list = asMapList(json['works']).map(Work.fromJson).toList();
    return WorksPage(
      works: list,
      page: asInt(json['page'], 1),
      pageSize: asInt(json['pageSize'], list.isEmpty ? 20 : list.length),
      totalCount: asInt(json['totalCount'], list.length),
    );
  }

  static const empty = WorksPage(
    works: [],
    page: 1,
    pageSize: 20,
    totalCount: 0,
  );
}
