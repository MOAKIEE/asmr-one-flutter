import 'common.dart';

/// 作品评论 / 评分。
///
/// 该接口需要登录，字段在不同版本间略有差异，因此做了宽松解析。
class Review {
  const Review({
    required this.id,
    required this.workId,
    required this.rating,
    this.text,
    this.progress,
    this.createdAt,
    this.updatedAt,
    this.userId,
    this.userName,
  });

  final int id;
  final int workId;

  /// 1~5 星。
  final int rating;
  final String? text;

  /// 收听进度，例如 `已听完` / `进度 50%`。
  final String? progress;
  final String? createdAt;
  final String? updatedAt;
  final String? userId;
  final String? userName;

  bool get hasText => (text ?? '').trim().isNotEmpty;

  factory Review.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    return Review(
      id: asInt(json['id']),
      workId: asInt(json['work_id']),
      rating: asInt(json['rating']),
      text:
          asStringOrNull(json['review_text']) ??
          asStringOrNull(json['reviewText']) ??
          asStringOrNull(json['text']),
      progress: asStringOrNull(json['progress']),
      createdAt:
          asStringOrNull(json['created_at']) ??
          asStringOrNull(json['createdAt']),
      updatedAt:
          asStringOrNull(json['updated_at']) ??
          asStringOrNull(json['updatedAt']),
      userId:
          asStringOrNull(json['user_id']) ??
          (user.isEmpty ? null : asStringOrNull(user['id'])),
      userName:
          asStringOrNull(json['user_name']) ??
          asStringOrNull(json['userName']) ??
          (user.isEmpty
              ? null
              : (asStringOrNull(user['name']) ??
                    asStringOrNull(user['nickname']))),
    );
  }
}

/// 评论列表分页结果。
class ReviewPage {
  const ReviewPage({
    required this.reviews,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<Review> reviews;
  final int page;
  final int pageSize;
  final int totalCount;

  bool get hasMore => page * pageSize < totalCount;

  factory ReviewPage.fromJson(Map<String, dynamic> json) {
    // 兼容 `{reviews: [...]}` / `{data: [...]}` / 直接数组 三种形态。
    final raw = json['reviews'] ?? json['data'] ?? json['list'];
    final list = asMapList(raw).map(Review.fromJson).toList();
    return ReviewPage(
      reviews: list,
      page: asInt(json['page'], 1),
      pageSize: asInt(json['pageSize'], list.isEmpty ? 20 : list.length),
      totalCount: asInt(json['totalCount'], list.length),
    );
  }

  static const empty = ReviewPage(
    reviews: [],
    page: 1,
    pageSize: 20,
    totalCount: 0,
  );
}
