import '../../core/models/common.dart';

/// 内置标签目录（自动生成，数据来源：asmr.one 热门作品标签统计）。
///
/// 未登录时接口不开放 `/api/tags`，这里内置一份热门标签用于筛选面板；
/// 登录后 `TagRepository` 会用服务端返回的完整目录覆盖它。
///
/// 重新生成：`python tool/gen_tag_catalog.py`。
class BundledTags {
  const BundledTags._();

  /// 数据版本，用于判断是否需要刷新内置目录。
  static const int version = 1;

  static const List<Tag> all = [
    Tag(
      id: 128,
      name: '内射/中出',
      i18n: {
        'zh-cn': {'name': '内射/中出'},
        'ja-jp': {'name': '中出し'},
        'en-us': {'name': 'Internal Cumshot'},
      },
      count: 1837,
    ),
    Tag(
      id: 496,
      name: '双声道立体声/人头麦',
      i18n: {
        'zh-cn': {'name': '双声道立体声/人头麦'},
        'ja-jp': {'name': 'バイノーラル/ダミヘ'},
        'en-us': {'name': 'Binaural'},
      },
      count: 1458,
    ),
    Tag(
      id: 4,
      name: '亲热/甜蜜',
      i18n: {
        'zh-cn': {'name': '亲热/甜蜜'},
        'ja-jp': {'name': 'ラブラブ/あまあま'},
        'en-us': {'name': 'Lovey Dovey / Sweet Love'},
      },
      count: 1352,
    ),
    Tag(
      id: 500,
      name: '舔耳',
      i18n: {
        'zh-cn': {'name': '舔耳'},
        'ja-jp': {'name': '耳舐め'},
        'en-us': {'name': 'Ear Licking'},
      },
      count: 1343,
    ),
    Tag(
      id: 497,
      name: 'ASMR',
      i18n: {
        'zh-cn': {'name': 'ASMR'},
        'ja-jp': {'name': 'ASMR'},
        'en-us': {'name': 'ASMR'},
      },
      count: 1251,
    ),
    Tag(
      id: 138,
      name: '口交',
      i18n: {
        'zh-cn': {'name': '口交'},
        'ja-jp': {'name': 'フェラチオ'},
        'en-us': {'name': 'Blowjob / Fellatio'},
      },
      count: 1092,
    ),
    Tag(
      id: 524,
      name: '哦吼淫叫',
      i18n: {
        'zh-cn': {'name': '哦吼淫叫'},
        'ja-jp': {'name': 'オホ声'},
        'en-us': {'name': 'Vulgar Moans'},
      },
      count: 828,
    ),
    Tag(
      id: 124,
      name: '手交',
      i18n: {
        'zh-cn': {'name': '手交'},
        'ja-jp': {'name': '手コキ'},
        'en-us': {'name': 'Hand Job'},
      },
      count: 800,
    ),
    Tag(
      id: 182,
      name: '巨乳/爆乳',
      i18n: {
        'zh-cn': {'name': '巨乳/爆乳'},
        'ja-jp': {'name': '巨乳/爆乳'},
        'en-us': {'name': 'Big Breasts'},
      },
      count: 745,
    ),
    Tag(
      id: 56,
      name: '治愈',
      i18n: {
        'zh-cn': {'name': '治愈'},
        'ja-jp': {'name': '癒し'},
        'en-us': {'name': 'Healing'},
      },
      count: 734,
    ),
    Tag(
      id: 503,
      name: '低语',
      i18n: {
        'zh-cn': {'name': '低语'},
        'ja-jp': {'name': 'ささやき'},
        'en-us': {'name': 'Whispering'},
      },
      count: 716,
    ),
    Tag(
      id: 156,
      name: '男性受',
      i18n: {
        'zh-cn': {'name': '男性受'},
        'ja-jp': {'name': '男性受け'},
        'en-us': {'name': 'Submissive Man'},
      },
      count: 644,
    ),
    Tag(
      id: 193,
      name: '处女',
      i18n: {
        'zh-cn': {'name': '处女'},
        'ja-jp': {'name': '処女'},
        'en-us': {'name': 'Virgin Female'},
      },
      count: 624,
    ),
    Tag(
      id: 122,
      name: '乳交',
      i18n: {
        'zh-cn': {'name': '乳交'},
        'ja-jp': {'name': 'パイズリ'},
        'en-us': {'name': 'Breast Sex'},
      },
      count: 530,
    ),
    Tag(
      id: 68,
      name: '淫语',
      i18n: {
        'zh-cn': {'name': '淫语'},
        'ja-jp': {'name': '淫語'},
        'en-us': {'name': 'Dirty Talk'},
      },
      count: 477,
    ),
    Tag(
      id: 144,
      name: '言语刺激',
      i18n: {
        'zh-cn': {'name': '言语刺激'},
        'ja-jp': {'name': '言葉責め'},
        'en-us': {'name': 'Verbal Humiliation'},
      },
      count: 412,
    ),
    Tag(
      id: 70,
      name: '连续高潮',
      i18n: {
        'zh-cn': {'name': '连续高潮'},
        'ja-jp': {'name': '連続絶頂'},
        'en-us': {'name': 'Successive Orgasms'},
      },
      count: 401,
    ),
    Tag(
      id: 46,
      name: '后宫',
      i18n: {
        'zh-cn': {'name': '后宫'},
        'ja-jp': {'name': 'ハーレム'},
        'en-us': {'name': 'Harem'},
      },
      count: 343,
    ),
    Tag(
      id: 442,
      name: '掏耳',
      i18n: {
        'zh-cn': {'name': '掏耳'},
        'ja-jp': {'name': '耳かき'},
        'en-us': {'name': 'Ear Cleaning'},
      },
      count: 340,
    ),
    Tag(
      id: 160,
      name: '肛交',
      i18n: {
        'zh-cn': {'name': '肛交'},
        'ja-jp': {'name': 'アナル'},
        'en-us': {'name': 'Anal'},
      },
      count: 320,
    ),
    Tag(
      id: 116,
      name: '多P/乱交',
      i18n: {
        'zh-cn': {'name': '多P/乱交'},
        'ja-jp': {'name': '複数プレイ/乱交'},
        'en-us': {'name': 'Orgy Sex'},
      },
      count: 318,
    ),
    Tag(
      id: 135,
      name: '自慰',
      i18n: {
        'zh-cn': {'name': '自慰'},
        'ja-jp': {'name': 'オナニー'},
        'en-us': {'name': 'Masturbation'},
      },
      count: 304,
    ),
    Tag(
      id: 400,
      name: '学生',
      i18n: {
        'zh-cn': {'name': '学生'},
        'ja-jp': {'name': '学生'},
        'en-us': {'name': 'Student'},
      },
      count: 290,
    ),
    Tag(
      id: 514,
      name: '自慰辅助',
      i18n: {
        'zh-cn': {'name': '自慰辅助'},
        'ja-jp': {'name': 'オナサポ'},
        'en-us': {'name': 'Guided Masturbation'},
      },
      count: 289,
    ),
    Tag(
      id: 523,
      name: '乳头刺激',
      i18n: {
        'zh-cn': {'name': '乳头刺激'},
        'ja-jp': {'name': '乳首責め'},
        'en-us': {'name': 'Nipple Teasing'},
      },
      count: 289,
    ),
    Tag(
      id: 501,
      name: '潮吹',
      i18n: {
        'zh-cn': {'name': '潮吹'},
        'ja-jp': {'name': '潮吹き'},
        'en-us': {'name': 'Squirting / Gushing'},
      },
      count: 272,
    ),
    Tag(
      id: 416,
      name: '婊子',
      i18n: {
        'zh-cn': {'name': '婊子'},
        'ja-jp': {'name': 'ビッチ'},
        'en-us': {'name': 'Bitch / Slut'},
      },
      count: 254,
    ),
    Tag(
      id: 207,
      name: '萝莉',
      i18n: {
        'zh-cn': {'name': '萝莉'},
        'ja-jp': {'name': 'ロリ'},
        'en-us': {'name': 'Loli'},
      },
      count: 250,
    ),
    Tag(
      id: 129,
      name: '怀孕',
      i18n: {
        'zh-cn': {'name': '怀孕'},
        'ja-jp': {'name': '妊娠/孕ませ'},
        'en-us': {'name': 'Pregnancy / Impregnation'},
      },
      count: 249,
    ),
    Tag(
      id: 65,
      name: '胸部/奶子',
      i18n: {
        'zh-cn': {'name': '胸部/奶子'},
        'ja-jp': {'name': 'おっぱい'},
        'en-us': {'name': 'Breasts'},
      },
      count: 246,
    ),
    Tag(
      id: 152,
      name: '挑逗/调情',
      i18n: {
        'zh-cn': {'name': '挑逗/调情'},
        'ja-jp': {'name': '焦らし'},
        'en-us': {'name': 'Tease'},
      },
      count: 240,
    ),
    Tag(
      id: 115,
      name: '逆强奸/女上男',
      i18n: {
        'zh-cn': {'name': '逆强奸/女上男'},
        'ja-jp': {'name': '逆レイプ'},
        'en-us': {'name': 'Reverse Rape'},
      },
      count: 226,
    ),
    Tag(
      id: 6,
      name: '颓废/背德',
      i18n: {
        'zh-cn': {'name': '颓废/背德'},
        'ja-jp': {'name': '退廃/背徳/インモラル'},
        'en-us': {'name': 'Decadent / Immoral'},
      },
      count: 224,
    ),
    Tag(
      id: 536,
      name: '女性主导',
      i18n: {
        'zh-cn': {'name': '女性主导'},
        'ja-jp': {'name': '女性優位'},
        'en-us': {'name': 'Femdom'},
      },
      count: 223,
    ),
    Tag(
      id: 48,
      name: '被NTR(苦主视角)',
      i18n: {
        'zh-cn': {'name': '被NTR(苦主视角)'},
        'ja-jp': {'name': '寝取られ'},
        'en-us': {'name': 'Cuckoldry (Netorare)'},
      },
      count: 222,
    ),
    Tag(
      id: 32,
      name: '纯爱',
      i18n: {
        'zh-cn': {'name': '纯爱'},
        'ja-jp': {'name': '純愛'},
        'en-us': {'name': 'Pure Love'},
      },
      count: 220,
    ),
    Tag(
      id: 1,
      name: '学校/学园',
      i18n: {
        'zh-cn': {'name': '学校/学园'},
        'ja-jp': {'name': '学校/学園'},
        'en-us': {'name': 'School / Academy'},
      },
      count: 195,
    ),
    Tag(
      id: 8,
      name: '日常/生活',
      i18n: {
        'zh-cn': {'name': '日常/生活'},
        'ja-jp': {'name': '日常/生活'},
        'en-us': {'name': 'Slice of Life / Daily Living'},
      },
      count: 187,
    ),
    Tag(
      id: 10000,
      name: 'AI',
      i18n: {
        'zh-cn': {'name': 'AI'},
        'ja-jp': {'name': 'AI'},
        'en-us': {'name': 'AI'},
      },
      count: 186,
    ),
    Tag(
      id: 114,
      name: '强制/硬上',
      i18n: {
        'zh-cn': {'name': '强制/硬上'},
        'ja-jp': {'name': '強制/無理矢理'},
        'en-us': {'name': 'Coercion / Compulsion'},
      },
      count: 185,
    ),
    Tag(
      id: 491,
      name: '女性向',
      i18n: {
        'zh-cn': {'name': '女性向'},
        'ja-jp': {'name': '女性向'},
        'en-us': {'name': '女性向'},
      },
      count: 183,
    ),
    Tag(
      id: 14,
      name: '情侣',
      i18n: {
        'zh-cn': {'name': '情侣'},
        'ja-jp': {'name': '恋人同士'},
        'en-us': {'name': 'Lovers'},
      },
      count: 180,
    ),
    Tag(
      id: 10001,
      name: '乙女向',
      i18n: {
        'zh-cn': {'name': '乙女向'},
        'ja-jp': {'name': '乙女向'},
        'en-us': {'name': '乙女向'},
      },
      count: 180,
    ),
    Tag(
      id: 526,
      name: '沉迷快乐/快乐堕落',
      i18n: {
        'zh-cn': {'name': '沉迷快乐/快乐堕落'},
        'ja-jp': {'name': '快楽堕ち'},
        'en-us': {'name': 'Pleasure Corruption'},
      },
      count: 178,
    ),
    Tag(
      id: 140,
      name: '调教',
      i18n: {
        'zh-cn': {'name': '调教'},
        'ja-jp': {'name': '調教'},
        'en-us': {'name': 'Sexual Training'},
      },
      count: 176,
    ),
    Tag(
      id: 51,
      name: '萌',
      i18n: {
        'zh-cn': {'name': '萌'},
        'ja-jp': {'name': '萌え'},
        'en-us': {'name': 'Moe'},
      },
      count: 174,
    ),
    Tag(
      id: 78,
      name: '女仆',
      i18n: {
        'zh-cn': {'name': '女仆'},
        'ja-jp': {'name': 'メイド'},
        'en-us': {'name': 'Maid'},
      },
      count: 173,
    ),
    Tag(
      id: 489,
      name: '吞精/食精',
      i18n: {
        'zh-cn': {'name': '吞精/食精'},
        'ja-jp': {'name': 'ごっくん/食ザー'},
        'en-us': {'name': 'Cum Swallowing'},
      },
      count: 173,
    ),
    Tag(
      id: 433,
      name: '无逆转',
      i18n: {
        'zh-cn': {'name': '无逆转'},
        'ja-jp': {'name': '逆転無し'},
        'en-us': {'name': 'No Reverse'},
      },
      count: 163,
    ),
    Tag(
      id: 488,
      name: '口内射精/口爆',
      i18n: {
        'zh-cn': {'name': '口内射精/口爆'},
        'ja-jp': {'name': '口内射精'},
        'en-us': {'name': 'Oral Cumshot'},
      },
      count: 162,
    ),
    Tag(
      id: 637,
      name: '亲吻',
      i18n: {
        'zh-cn': {'name': '亲吻'},
        'ja-jp': {'name': 'キス'},
        'en-us': {'name': 'Kissing'},
      },
      count: 162,
    ),
    Tag(
      id: 302,
      name: 'NTR(黄毛视角)',
      i18n: {
        'zh-cn': {'name': 'NTR(黄毛视角)'},
        'ja-jp': {'name': '寝取り'},
        'en-us': {'name': 'Cuckoldry (Netori)'},
      },
      count: 155,
    ),
    Tag(
      id: 296,
      name: '系列作品',
      i18n: {
        'zh-cn': {'name': '系列作品'},
        'ja-jp': {'name': 'シリーズもの'},
        'en-us': {'name': 'Serial Product'},
      },
      count: 154,
    ),
    Tag(
      id: 157,
      name: '催眠',
      i18n: {
        'zh-cn': {'name': '催眠'},
        'ja-jp': {'name': '催眠'},
        'en-us': {'name': 'Hypnosis'},
      },
      count: 153,
    ),
    Tag(
      id: 487,
      name: '深喉口交(男主导)',
      i18n: {
        'zh-cn': {'name': '深喉口交(男主导)'},
        'ja-jp': {'name': 'イラマチオ'},
        'en-us': {'name': 'Irrumatio'},
      },
      count: 153,
    ),
    Tag(
      id: 506,
      name: '魅魔/淫魔',
      i18n: {
        'zh-cn': {'name': '魅魔/淫魔'},
        'ja-jp': {'name': 'サキュバス/淫魔'},
        'en-us': {'name': 'Succubus / Incubus'},
      },
      count: 149,
    ),
    Tag(
      id: 142,
      name: '淫乱',
      i18n: {
        'zh-cn': {'name': '淫乱'},
        'ja-jp': {'name': '淫乱'},
        'en-us': {'name': 'Naughty / Lewd'},
      },
      count: 149,
    ),
    Tag(
      id: 220,
      name: '姐姐',
      i18n: {
        'zh-cn': {'name': '姐姐'},
        'ja-jp': {'name': 'お姉さん'},
        'en-us': {'name': 'Oneesan / Older Girl / Older Sister'},
      },
      count: 148,
    ),
    Tag(
      id: 528,
      name: '无插入/无正戏',
      i18n: {
        'zh-cn': {'name': '无插入/无正戏'},
        'ja-jp': {'name': '本番なし'},
        'en-us': {'name': 'No Penetrative Sex'},
      },
      count: 139,
    ),
    Tag(
      id: 125,
      name: '足交',
      i18n: {
        'zh-cn': {'name': '足交'},
        'ja-jp': {'name': '足コキ'},
        'en-us': {'name': 'Foot Job'},
      },
      count: 137,
    ),
    Tag(
      id: 16,
      name: '奇幻',
      i18n: {
        'zh-cn': {'name': '奇幻'},
        'ja-jp': {'name': 'ファンタジー'},
        'en-us': {'name': 'Fantasy'},
      },
      count: 136,
    ),
    Tag(
      id: 66,
      name: '特殊癖好/变态',
      i18n: {
        'zh-cn': {'name': '特殊癖好/变态'},
        'ja-jp': {'name': 'マニアック/変態'},
        'en-us': {'name': 'Abnormal / Perverted'},
      },
      count: 133,
    ),
    Tag(
      id: 314,
      name: '催眠音声',
      i18n: {
        'zh-cn': {'name': '催眠音声'},
        'ja-jp': {'name': '催眠音声'},
        'en-us': {'name': 'Hypnotic Voice'},
      },
      count: 124,
    ),
    Tag(
      id: 415,
      name: '辣妹',
      i18n: {
        'zh-cn': {'name': '辣妹'},
        'ja-jp': {'name': 'ギャル'},
        'en-us': {'name': 'Gal'},
      },
      count: 124,
    ),
    Tag(
      id: 448,
      name: '色诱',
      i18n: {
        'zh-cn': {'name': '色诱'},
        'ja-jp': {'name': '色仕掛け'},
        'en-us': {'name': 'Coquettish / Seduction'},
      },
      count: 118,
    ),
    Tag(
      id: 149,
      name: '羞耻/耻辱',
      i18n: {
        'zh-cn': {'name': '羞耻/耻辱'},
        'ja-jp': {'name': '羞恥/恥辱'},
        'en-us': {'name': 'Shame / Humiliation'},
      },
      count: 117,
    ),
    Tag(
      id: 222,
      name: '青梅竹马',
      i18n: {
        'zh-cn': {'name': '青梅竹马'},
        'ja-jp': {'name': '幼なじみ'},
        'en-us': {'name': 'Childhood Friend'},
      },
      count: 111,
    ),
    Tag(
      id: 285,
      name: '前辈/后辈',
      i18n: {
        'zh-cn': {'name': '前辈/后辈'},
        'ja-jp': {'name': '先輩/後輩'},
        'en-us': {'name': 'Junior / Senior (at work, school, etc)'},
      },
      count: 111,
    ),
    Tag(
      id: 130,
      name: '母乳',
      i18n: {
        'zh-cn': {'name': '母乳'},
        'ja-jp': {'name': '母乳'},
        'en-us': {'name': 'Breast Milk'},
      },
      count: 104,
    ),
    Tag(
      id: 159,
      name: '放尿/小便',
      i18n: {
        'zh-cn': {'name': '放尿/小便'},
        'ja-jp': {'name': '放尿/おしっこ'},
        'en-us': {'name': 'Urination / Peeing'},
      },
      count: 102,
    ),
    Tag(
      id: 504,
      name: '姐姐×正太',
      i18n: {
        'zh-cn': {'name': '姐姐×正太'},
        'ja-jp': {'name': 'おねショタ'},
        'en-us': {'name': 'Elder Girl x Younger Boy'},
      },
      count: 101,
    ),
    Tag(
      id: 540,
      name: '婴儿PLAY',
      i18n: {
        'zh-cn': {'name': '婴儿PLAY'},
        'ja-jp': {'name': '赤ちゃんプレイ'},
        'en-us': {'name': 'Babyplay'},
      },
      count: 94,
    ),
    Tag(
      id: 513,
      name: 'VTuber',
      i18n: {
        'zh-cn': {'name': 'VTuber'},
        'ja-jp': {'name': 'VTuber'},
        'en-us': {'name': 'VTuber'},
      },
      count: 93,
    ),
    Tag(
      id: 525,
      name: '雌小鬼',
      i18n: {
        'zh-cn': {'name': '雌小鬼'},
        'ja-jp': {'name': 'メスガキ'},
        'en-us': {'name': 'Mesugaki'},
      },
      count: 91,
    ),
    Tag(
      id: 263,
      name: '玩具',
      i18n: {
        'zh-cn': {'name': '玩具'},
        'ja-jp': {'name': 'おもちゃ'},
        'en-us': {'name': 'Toys'},
      },
      count: 90,
    ),
    Tag(
      id: 64,
      name: '癖好/性趣',
      i18n: {
        'zh-cn': {'name': '癖好/性趣'},
        'ja-jp': {'name': 'フェチ'},
        'en-us': {'name': 'Fetish'},
      },
      count: 88,
    ),
    Tag(
      id: 58,
      name: '皆大欢喜',
      i18n: {
        'zh-cn': {'name': '皆大欢喜'},
        'ja-jp': {'name': 'オールハッピー'},
        'en-us': {'name': 'Totally Happy'},
      },
      count: 88,
    ),
    Tag(
      id: 446,
      name: '卖春/援交',
      i18n: {
        'zh-cn': {'name': '卖春/援交'},
        'ja-jp': {'name': '売春/援交'},
        'en-us': {'name': 'Prostitution / Paid Dating'},
      },
      count: 86,
    ),
    Tag(
      id: 219,
      name: '人妻',
      i18n: {
        'zh-cn': {'name': '人妻'},
        'ja-jp': {'name': '人妻'},
        'en-us': {'name': 'Married Woman'},
      },
      count: 85,
    ),
    Tag(
      id: 447,
      name: '风俗/泡泡浴',
      i18n: {
        'zh-cn': {'name': '风俗/泡泡浴'},
        'ja-jp': {'name': '風俗/ソープ'},
        'en-us': {'name': 'Sex Industry / Soapland'},
      },
      count: 83,
    ),
    Tag(
      id: 409,
      name: '艺人/偶像/模特',
      i18n: {
        'zh-cn': {'name': '艺人/偶像/模特'},
        'ja-jp': {'name': '芸能人/アイドル/モデル'},
        'en-us': {'name': 'Entertainer / Idol / Model'},
      },
      count: 82,
    ),
    Tag(
      id: 74,
      name: '制服',
      i18n: {
        'zh-cn': {'name': '制服'},
        'ja-jp': {'name': '制服'},
        'en-us': {'name': 'Uniform'},
      },
      count: 82,
    ),
    Tag(
      id: 69,
      name: '大量汁/液',
      i18n: {
        'zh-cn': {'name': '大量汁/液'},
        'ja-jp': {'name': '汁/液大量'},
        'en-us': {'name': 'Lots of White Cream / Juices'},
      },
      count: 81,
    ),
    Tag(
      id: 440,
      name: '出轨',
      i18n: {
        'zh-cn': {'name': '出轨'},
        'ja-jp': {'name': '浮気'},
        'en-us': {'name': 'Cheating / Adultery'},
      },
      count: 81,
    ),
    Tag(
      id: 441,
      name: '非虚构/纪实',
      i18n: {
        'zh-cn': {'name': '非虚构/纪实'},
        'ja-jp': {'name': 'ノンフィクション/体験談'},
        'en-us': {'name': 'Non-fiction / Real Story'},
      },
      count: 80,
    ),
    Tag(
      id: 437,
      name: '初体验',
      i18n: {
        'zh-cn': {'name': '初体验'},
        'ja-jp': {'name': '初体験'},
        'en-us': {'name': 'First Experience'},
      },
      count: 79,
    ),
    Tag(
      id: 235,
      name: '精灵/妖精',
      i18n: {
        'zh-cn': {'name': '精灵/妖精'},
        'ja-jp': {'name': 'エルフ/妖精'},
        'en-us': {'name': 'Elf / Fairy'},
      },
      count: 76,
    ),
    Tag(
      id: 499,
      name: '舔阴',
      i18n: {
        'zh-cn': {'name': '舔阴'},
        'ja-jp': {'name': 'クンニ'},
        'en-us': {'name': 'Cunnilingus'},
      },
      count: 74,
    ),
    Tag(
      id: 317,
      name: '人外娘/魔物娘',
      i18n: {
        'zh-cn': {'name': '人外娘/魔物娘'},
        'ja-jp': {'name': '人外娘/モンスター娘'},
        'en-us': {'name': 'Nonhuman / Monster Girl'},
      },
      count: 72,
    ),
    Tag(
      id: 638,
      name: '吹耳朵',
      i18n: {
        'zh-cn': {'name': '吹耳朵'},
        'ja-jp': {'name': '耳ふー'},
        'en-us': {'name': 'Ear Blowing'},
      },
      count: 69,
    ),
    Tag(
      id: 19,
      name: '恐怖',
      i18n: {
        'zh-cn': {'name': '恐怖'},
        'ja-jp': {'name': 'ホラー'},
        'en-us': {'name': 'Horror'},
      },
      count: 69,
    ),
    Tag(
      id: 212,
      name: '妹妹',
      i18n: {
        'zh-cn': {'name': '妹妹'},
        'ja-jp': {'name': '妹'},
        'en-us': {'name': 'Younger Sister'},
      },
      count: 66,
    ),
    Tag(
      id: 206,
      name: '少女',
      i18n: {
        'zh-cn': {'name': '少女'},
        'ja-jp': {'name': '少女'},
        'en-us': {'name': 'Girl'},
      },
      count: 66,
    ),
    Tag(
      id: 326,
      name: '洗脑',
      i18n: {
        'zh-cn': {'name': '洗脑'},
        'ja-jp': {'name': '洗脳'},
        'en-us': {'name': 'Brainwashing'},
      },
      count: 66,
    ),
    Tag(
      id: 96,
      name: '修女',
      i18n: {
        'zh-cn': {'name': '修女'},
        'ja-jp': {'name': 'シスター'},
        'en-us': {'name': 'Sister / Nun'},
      },
      count: 64,
    ),
    Tag(
      id: 522,
      name: '雌堕',
      i18n: {
        'zh-cn': {'name': '雌堕'},
        'ja-jp': {'name': 'メス堕ち'},
        'en-us': {'name': 'Fem-corruption'},
      },
      count: 63,
    ),
    Tag(
      id: 529,
      name: '故意被NTR/绿奴',
      i18n: {
        'zh-cn': {'name': '故意被NTR/绿奴'},
        'ja-jp': {'name': '寝取らせ'},
        'en-us': {'name': 'Cuckoldry (Netorase)'},
      },
      count: 63,
    ),
    Tag(
      id: 268,
      name: '姐妹',
      i18n: {
        'zh-cn': {'name': '姐妹'},
        'ja-jp': {'name': '姉妹'},
        'en-us': {'name': 'Sisters'},
      },
      count: 62,
    ),
    Tag(
      id: 113,
      name: '强奸',
      i18n: {
        'zh-cn': {'name': '强奸'},
        'ja-jp': {'name': 'レイプ'},
        'en-us': {'name': 'Rape'},
      },
      count: 62,
    ),
    Tag(
      id: 120,
      name: '近亲相奸',
      i18n: {
        'zh-cn': {'name': '近亲相奸'},
        'ja-jp': {'name': '近親相姦'},
        'en-us': {'name': 'Incest'},
      },
      count: 61,
    ),
    Tag(
      id: 464,
      name: '打屁股',
      i18n: {
        'zh-cn': {'name': '打屁股'},
        'ja-jp': {'name': 'スパンキング'},
        'en-us': {'name': 'Spanking'},
      },
      count: 59,
    ),
    Tag(
      id: 316,
      name: '病娇',
      i18n: {
        'zh-cn': {'name': '病娇'},
        'ja-jp': {'name': 'ヤンデレ'},
        'en-us': {'name': 'Yandere'},
      },
      count: 55,
    ),
    Tag(
      id: 530,
      name: '逆NTR',
      i18n: {
        'zh-cn': {'name': '逆NTR'},
        'ja-jp': {'name': '逆NTR'},
        'en-us': {'name': 'Reverse Cuckoldry'},
      },
      count: 54,
    ),
    Tag(
      id: 281,
      name: '同学/同事',
      i18n: {
        'zh-cn': {'name': '同学/同事'},
        'ja-jp': {'name': '同級生/同僚'},
        'en-us': {'name': 'Classmate / Colleague'},
      },
      count: 52,
    ),
    Tag(
      id: 209,
      name: '年上',
      i18n: {
        'zh-cn': {'name': '年上'},
        'ja-jp': {'name': '年上'},
        'en-us': {'name': 'Senior'},
      },
      count: 50,
    ),
    Tag(
      id: 143,
      name: '露出',
      i18n: {
        'zh-cn': {'name': '露出'},
        'ja-jp': {'name': '露出'},
        'en-us': {'name': 'Outdoor Exposure'},
      },
      count: 50,
    ),
    Tag(
      id: 192,
      name: '童贞/处男',
      i18n: {
        'zh-cn': {'name': '童贞/处男'},
        'ja-jp': {'name': '童貞'},
        'en-us': {'name': 'Virgin Male'},
      },
      count: 50,
    ),
    Tag(
      id: 323,
      name: '高潮脸/阿黑颜',
      i18n: {
        'zh-cn': {'name': '高潮脸/阿黑颜'},
        'ja-jp': {'name': 'アヘ顔'},
        'en-us': {'name': 'Ahegao / Gapeface'},
      },
      count: 49,
    ),
    Tag(
      id: 158,
      name: '百合',
      i18n: {
        'zh-cn': {'name': '百合'},
        'ja-jp': {'name': '百合'},
        'en-us': {'name': 'Yuri / Girls Love'},
      },
      count: 49,
    ),
    Tag(
      id: 176,
      name: '兽耳',
      i18n: {
        'zh-cn': {'name': '兽耳'},
        'ja-jp': {'name': '獣耳'},
        'en-us': {'name': 'Animal Ears'},
      },
      count: 48,
    ),
    Tag(
      id: 223,
      name: '双胞胎',
      i18n: {
        'zh-cn': {'name': '双胞胎'},
        'ja-jp': {'name': '双子'},
        'en-us': {'name': 'Twins'},
      },
      count: 48,
    ),
    Tag(
      id: 146,
      name: '拘束',
      i18n: {
        'zh-cn': {'name': '拘束'},
        'ja-jp': {'name': '拘束'},
        'en-us': {'name': 'Restraint'},
      },
      count: 47,
    ),
    Tag(
      id: 136,
      name: 'SM',
      i18n: {
        'zh-cn': {'name': 'SM'},
        'ja-jp': {'name': 'SM'},
        'en-us': {'name': 'SM'},
      },
      count: 47,
    ),
    Tag(
      id: 53,
      name: '健全',
      i18n: {
        'zh-cn': {'name': '健全'},
        'ja-jp': {'name': '健全'},
        'en-us': {'name': 'Wholesome'},
      },
      count: 46,
    ),
    Tag(
      id: 80,
      name: '巫女',
      i18n: {
        'zh-cn': {'name': '巫女'},
        'ja-jp': {'name': '巫女'},
        'en-us': {'name': 'Shrine Maiden'},
      },
      count: 44,
    ),
    Tag(
      id: 86,
      name: 'Cosplay/角色扮演',
      i18n: {
        'zh-cn': {'name': 'Cosplay/角色扮演'},
        'ja-jp': {'name': 'コスプレ'},
        'en-us': {'name': 'Cosplay'},
      },
      count: 44,
    ),
    Tag(
      id: 13,
      name: '温馨',
      i18n: {
        'zh-cn': {'name': '温馨'},
        'ja-jp': {'name': 'ほのぼの'},
        'en-us': {'name': 'Heartwarming'},
      },
      count: 44,
    ),
    Tag(
      id: 35,
      name: '失禁',
      i18n: {
        'zh-cn': {'name': '失禁'},
        'ja-jp': {'name': 'おもらし'},
        'en-us': {'name': 'Peeing Oneself'},
      },
      count: 43,
    ),
    Tag(
      id: 646,
      name: '龟头刺激',
      i18n: {
        'zh-cn': {'name': '龟头刺激'},
        'ja-jp': {'name': '亀頭責め'},
        'en-us': {'name': 'Glans Stimulation'},
      },
      count: 43,
    ),
    Tag(
      id: 183,
      name: '贫乳/微乳',
      i18n: {
        'zh-cn': {'name': '贫乳/微乳'},
        'ja-jp': {'name': '貧乳/微乳'},
        'en-us': {'name': 'Tiny Breasts'},
      },
      count: 43,
    ),
    Tag(
      id: 636,
      name: '陪睡',
      i18n: {
        'zh-cn': {'name': '陪睡'},
        'ja-jp': {'name': '添い寝'},
        'en-us': {'name': 'Co-sleeping'},
      },
      count: 43,
    ),
    Tag(
      id: 179,
      name: '丰满',
      i18n: {
        'zh-cn': {'name': '丰满'},
        'ja-jp': {'name': 'ムチムチ'},
        'en-us': {'name': 'Voluptuous / Plump'},
      },
      count: 42,
    ),
    Tag(
      id: 321,
      name: '褐皮/晒痕',
      i18n: {
        'zh-cn': {'name': '褐皮/晒痕'},
        'ja-jp': {'name': '褐色/日焼け'},
        'en-us': {'name': 'Tanned Skin / Suntan'},
      },
      count: 41,
    ),
    Tag(
      id: 649,
      name: '模仿娇喘',
      i18n: {
        'zh-cn': {'name': '模仿娇喘'},
        'ja-jp': {'name': '喘ぎ真似'},
        'en-us': {'name': 'Moan Imitation'},
      },
      count: 41,
    ),
    Tag(
      id: 187,
      name: '平胸/飞机场',
      i18n: {
        'zh-cn': {'name': '平胸/飞机场'},
        'ja-jp': {'name': 'ツルペタ'},
        'en-us': {'name': 'Tsurupeta'},
      },
      count: 41,
    ),
    Tag(
      id: 59,
      name: '傲娇',
      i18n: {
        'zh-cn': {'name': '傲娇'},
        'ja-jp': {'name': 'ツンデレ'},
        'en-us': {'name': 'Tsundere'},
      },
      count: 40,
    ),
    Tag(
      id: 57,
      name: '平淡/冷淡',
      i18n: {
        'zh-cn': {'name': '平淡/冷淡'},
        'ja-jp': {'name': '淡白/あっさり'},
        'en-us': {'name': 'Plain / Nonpersisting'},
      },
      count: 40,
    ),
    Tag(
      id: 190,
      name: '扶她',
      i18n: {
        'zh-cn': {'name': '扶她'},
        'ja-jp': {'name': 'フタナリ'},
        'en-us': {'name': 'Futanari / Hermaphrodite'},
      },
      count: 38,
    ),
    Tag(
      id: 121,
      name: '轮奸',
      i18n: {
        'zh-cn': {'name': '轮奸'},
        'ja-jp': {'name': '輪姦'},
        'en-us': {'name': 'Gangbang'},
      },
      count: 36,
    ),
    Tag(
      id: 91,
      name: '浴衣/和服',
      i18n: {
        'zh-cn': {'name': '浴衣/和服'},
        'ja-jp': {'name': '着物/和服'},
        'en-us': {'name': 'Kimono / Japanese Clothes'},
      },
      count: 36,
    ),
    Tag(
      id: 134,
      name: '凌辱',
      i18n: {
        'zh-cn': {'name': '凌辱'},
        'ja-jp': {'name': '陵辱'},
        'en-us': {'name': 'Violation'},
      },
      count: 36,
    ),
    Tag(
      id: 99,
      name: '兔女郎',
      i18n: {
        'zh-cn': {'name': '兔女郎'},
        'ja-jp': {'name': 'バニーガール'},
        'en-us': {'name': 'Bunny Girl'},
      },
      count: 36,
    ),
    Tag(
      id: 151,
      name: '监禁',
      i18n: {
        'zh-cn': {'name': '监禁'},
        'ja-jp': {'name': '監禁'},
        'en-us': {'name': 'Captivity'},
      },
      count: 35,
    ),
    Tag(
      id: 127,
      name: '颜射',
      i18n: {
        'zh-cn': {'name': '颜射'},
        'ja-jp': {'name': '顔射'},
        'en-us': {'name': 'Facial Cumshot'},
      },
      count: 35,
    ),
    Tag(
      id: 532,
      name: '逆肛交',
      i18n: {
        'zh-cn': {'name': '逆肛交'},
        'ja-jp': {'name': '逆アナル'},
        'en-us': {'name': 'Reverse Anal'},
      },
      count: 35,
    ),
    Tag(
      id: 197,
      name: '男性自称少女/仆娘',
      i18n: {
        'zh-cn': {'name': '男性自称少女/仆娘'},
        'ja-jp': {'name': 'ボクっ娘'},
        'en-us': {'name': 'Boyish Girl'},
      },
      count: 34,
    ),
    Tag(
      id: 232,
      name: 'OL',
      i18n: {
        'zh-cn': {'name': 'OL'},
        'ja-jp': {'name': 'OL'},
        'en-us': {'name': 'Office Lady'},
      },
      count: 34,
    ),
    Tag(
      id: 256,
      name: '项圈/锁链/拘束道具',
      i18n: {
        'zh-cn': {'name': '项圈/锁链/拘束道具'},
        'ja-jp': {'name': '首輪/鎖/拘束具'},
        'en-us': {'name': 'Collar / Chain / Restraints'},
      },
      count: 34,
    ),
    Tag(
      id: 215,
      name: '女儿',
      i18n: {
        'zh-cn': {'name': '女儿'},
        'ja-jp': {'name': '娘'},
        'en-us': {'name': 'Daughter'},
      },
      count: 34,
    ),
    Tag(
      id: 3,
      name: '室外',
      i18n: {
        'zh-cn': {'name': '室外'},
        'ja-jp': {'name': '屋外'},
        'en-us': {'name': 'Outdoor'},
      },
      count: 33,
    ),
    Tag(
      id: 213,
      name: '母亲',
      i18n: {
        'zh-cn': {'name': '母亲'},
        'ja-jp': {'name': '母親'},
        'en-us': {'name': 'Mother'},
      },
      count: 33,
    ),
    Tag(
      id: 170,
      name: '金发',
      i18n: {
        'zh-cn': {'name': '金发'},
        'ja-jp': {'name': '金髪'},
        'en-us': {'name': 'Blonde Hair'},
      },
      count: 33,
    ),
    Tag(
      id: 234,
      name: '女王/公主',
      i18n: {
        'zh-cn': {'name': '女王/公主'},
        'ja-jp': {'name': '女王様/お姫様'},
        'en-us': {'name': 'Queen / Princess'},
      },
      count: 33,
    ),
    Tag(
      id: 198,
      name: '无表情',
      i18n: {
        'zh-cn': {'name': '无表情'},
        'ja-jp': {'name': '無表情'},
        'en-us': {'name': 'Expressionless / Deadpan'},
      },
      count: 32,
    ),
    Tag(
      id: 538,
      name: '妈妈',
      i18n: {
        'zh-cn': {'name': '妈妈'},
        'ja-jp': {'name': 'ママ'},
        'en-us': {'name': 'Mommie'},
      },
      count: 32,
    ),
    Tag(
      id: 660,
      name: '阴郁系',
      i18n: {
        'zh-cn': {'name': '阴郁系'},
        'ja-jp': {'name': 'ダウナー'},
        'en-us': {'name': 'Languid'},
      },
      count: 32,
    ),
    Tag(
      id: 266,
      name: '润滑液',
      i18n: {
        'zh-cn': {'name': '润滑液'},
        'ja-jp': {'name': 'ローション'},
        'en-us': {'name': 'Lotion'},
      },
      count: 31,
    ),
    Tag(
      id: 60,
      name: '女性视角',
      i18n: {
        'zh-cn': {'name': '女性视角'},
        'ja-jp': {'name': '女性視点'},
        'en-us': {'name': 'Woman\'s Viewpoint'},
      },
      count: 31,
    ),
    Tag(
      id: 185,
      name: '乳头/乳晕',
      i18n: {
        'zh-cn': {'name': '乳头/乳晕'},
        'ja-jp': {'name': '乳首/乳輪'},
        'en-us': {'name': 'Nipples / Areola'},
      },
      count: 30,
    ),
    Tag(
      id: 63,
      name: '臀部/屁股',
      i18n: {
        'zh-cn': {'name': '臀部/屁股'},
        'ja-jp': {'name': 'お尻/ヒップ'},
        'en-us': {'name': 'Buttocks'},
      },
      count: 30,
    ),
    Tag(
      id: 652,
      name: '溺爱',
      i18n: {
        'zh-cn': {'name': '溺爱'},
        'ja-jp': {'name': '溺愛'},
        'en-us': {'name': 'Infatuation'},
      },
      count: 30,
    ),
    Tag(
      id: 289,
      name: '诱受',
      i18n: {
        'zh-cn': {'name': '诱受'},
        'ja-jp': {'name': '誘い受け'},
        'en-us': {'name': 'Seductive (Submissive)'},
      },
      count: 29,
    ),
    Tag(
      id: 438,
      name: '婚前同居',
      i18n: {
        'zh-cn': {'name': '婚前同居'},
        'ja-jp': {'name': '同棲'},
        'en-us': {'name': 'Cohabitation'},
      },
      count: 29,
    ),
    Tag(
      id: 79,
      name: '护士',
      i18n: {
        'zh-cn': {'name': '护士'},
        'ja-jp': {'name': 'ナース'},
        'en-us': {'name': 'Nurse'},
      },
      count: 28,
    ),
    Tag(
      id: 191,
      name: '巨根',
      i18n: {
        'zh-cn': {'name': '巨根'},
        'ja-jp': {'name': '巨根'},
        'en-us': {'name': 'Large Cock'},
      },
      count: 28,
    ),
    Tag(
      id: 279,
      name: '年下攻',
      i18n: {
        'zh-cn': {'name': '年下攻'},
        'ja-jp': {'name': '年下攻め'},
        'en-us': {'name': 'Younger (Dominant)'},
      },
      count: 28,
    ),
    Tag(
      id: 237,
      name: '天使/恶魔',
      i18n: {
        'zh-cn': {'name': '天使/恶魔'},
        'ja-jp': {'name': '天使/悪魔'},
        'en-us': {'name': 'Angel / Demon'},
      },
      count: 28,
    ),
    Tag(
      id: 123,
      name: '通奸/和奸',
      i18n: {
        'zh-cn': {'name': '通奸/和奸'},
        'ja-jp': {'name': '和姦'},
        'en-us': {'name': 'Consensual Sex'},
      },
      count: 28,
    ),
    Tag(
      id: 186,
      name: '西瓜肚/孕妇',
      i18n: {
        'zh-cn': {'name': '西瓜肚/孕妇'},
        'ja-jp': {'name': 'ぼて腹/妊婦'},
        'en-us': {'name': 'Pregnant Woman'},
      },
      count: 28,
    ),
    Tag(
      id: 242,
      name: '大小姐',
      i18n: {
        'zh-cn': {'name': '大小姐'},
        'ja-jp': {'name': 'お嬢様'},
        'en-us': {'name': 'Upper-class Girl'},
      },
      count: 27,
    ),
    Tag(
      id: 118,
      name: '蕾丝/女同',
      i18n: {
        'zh-cn': {'name': '蕾丝/女同'},
        'ja-jp': {'name': 'レズ/女同士'},
        'en-us': {'name': 'Lesbian'},
      },
      count: 27,
    ),
    Tag(
      id: 324,
      name: '异种奸',
      i18n: {
        'zh-cn': {'name': '异种奸'},
        'ja-jp': {'name': '異種姦'},
        'en-us': {'name': 'Interspecies Sex'},
      },
      count: 27,
    ),
    Tag(
      id: 325,
      name: '恶堕',
      i18n: {
        'zh-cn': {'name': '恶堕'},
        'ja-jp': {'name': '悪堕ち'},
        'en-us': {'name': 'Corrupted Morals'},
      },
      count: 27,
    ),
    Tag(
      id: 218,
      name: '熟女',
      i18n: {
        'zh-cn': {'name': '熟女'},
        'ja-jp': {'name': '熟女'},
        'en-us': {'name': 'Mature Woman / MILF'},
      },
      count: 27,
    ),
    Tag(
      id: 2,
      name: '办公室/职场',
      i18n: {
        'zh-cn': {'name': '办公室/职场'},
        'ja-jp': {'name': 'オフィス/職場'},
        'en-us': {'name': 'Office / Workplace'},
      },
      count: 26,
    ),
    Tag(
      id: 515,
      name: '总集篇',
      i18n: {
        'zh-cn': {'name': '总集篇'},
        'ja-jp': {'name': '総集編'},
        'en-us': {'name': 'Compilation'},
      },
      count: 26,
    ),
    Tag(
      id: 145,
      name: '野外/野战',
      i18n: {
        'zh-cn': {'name': '野外/野战'},
        'ja-jp': {'name': '青姦'},
        'en-us': {'name': 'Outdoor Sex'},
      },
      count: 26,
    ),
    Tag(
      id: 659,
      name: '按摩',
      i18n: {
        'zh-cn': {'name': '按摩'},
        'ja-jp': {'name': 'マッサージ'},
        'en-us': {'name': 'Massage'},
      },
      count: 26,
    ),
    Tag(
      id: 73,
      name: '动画',
      i18n: {
        'zh-cn': {'name': '动画'},
        'ja-jp': {'name': 'アニメ'},
        'en-us': {'name': 'Anime'},
      },
      count: 25,
    ),
    Tag(
      id: 265,
      name: '药物',
      i18n: {
        'zh-cn': {'name': '药物'},
        'ja-jp': {'name': '薬物'},
        'en-us': {'name': 'Drugs'},
      },
      count: 25,
    ),
    Tag(
      id: 462,
      name: '直男/直女',
      i18n: {
        'zh-cn': {'name': '直男/直女'},
        'ja-jp': {'name': 'ノンケ'},
        'en-us': {'name': 'Heterosexual / Nonke'},
      },
      count: 25,
    ),
    Tag(
      id: 240,
      name: '魔法少女',
      i18n: {
        'zh-cn': {'name': '魔法少女'},
        'ja-jp': {'name': '魔法少女'},
        'en-us': {'name': 'Magical Girl'},
      },
      count: 25,
    ),
    Tag(
      id: 455,
      name: '爱情喜剧',
      i18n: {
        'zh-cn': {'name': '爱情喜剧'},
        'ja-jp': {'name': 'ラブコメ'},
        'en-us': {'name': 'Love Comedy / Romcom'},
      },
      count: 25,
    ),
    Tag(
      id: 427,
      name: '王子殿下/王子系',
      i18n: {
        'zh-cn': {'name': '王子殿下/王子系'},
        'ja-jp': {'name': '王子様/王子系'},
        'en-us': {'name': 'Prince / Royalty'},
      },
      count: 24,
    ),
    Tag(
      id: 254,
      name: '机器人/仿生人',
      i18n: {
        'zh-cn': {'name': '机器人/仿生人'},
        'ja-jp': {'name': 'ロボット/アンドロイド'},
        'en-us': {'name': 'Robot / Android'},
      },
      count: 23,
    ),
    Tag(
      id: 131,
      name: '挤奶',
      i18n: {
        'zh-cn': {'name': '挤奶'},
        'ja-jp': {'name': '搾乳'},
        'en-us': {'name': 'Milking'},
      },
      count: 23,
    ),
    Tag(
      id: 495,
      name: '睡眠奸',
      i18n: {
        'zh-cn': {'name': '睡眠奸'},
        'ja-jp': {'name': '睡眠姦'},
        'en-us': {'name': 'Sleep Sex'},
      },
      count: 22,
    ),
    Tag(
      id: 217,
      name: '义姐',
      i18n: {
        'zh-cn': {'name': '义姐'},
        'ja-jp': {'name': '義姉'},
        'en-us': {'name': 'Older Stepsister'},
      },
      count: 22,
    ),
    Tag(
      id: 527,
      name: '阴蒂刺激',
      i18n: {
        'zh-cn': {'name': '阴蒂刺激'},
        'ja-jp': {'name': 'クリ責め'},
        'en-us': {'name': 'Clit Teasing'},
      },
      count: 22,
    ),
    Tag(
      id: 61,
      name: '致郁',
      i18n: {
        'zh-cn': {'name': '致郁'},
        'ja-jp': {'name': '鬱'},
        'en-us': {'name': 'Depression / Depressing'},
      },
      count: 22,
    ),
    Tag(
      id: 162,
      name: '触手',
      i18n: {
        'zh-cn': {'name': '触手'},
        'ja-jp': {'name': '触手'},
        'en-us': {'name': 'Tentacle'},
      },
      count: 21,
    ),
    Tag(
      id: 290,
      name: '高冷攻',
      i18n: {
        'zh-cn': {'name': '高冷攻'},
        'ja-jp': {'name': 'クール攻め'},
        'en-us': {'name': 'Cool Attitude (Dominant)'},
      },
      count: 21,
    ),
    Tag(
      id: 201,
      name: '拷问',
      i18n: {
        'zh-cn': {'name': '拷问'},
        'ja-jp': {'name': '拷問'},
        'en-us': {'name': 'Torture'},
      },
      count: 21,
    ),
    Tag(
      id: 161,
      name: '粪便/排泄物',
      i18n: {
        'zh-cn': {'name': '粪便/排泄物'},
        'ja-jp': {'name': 'スカトロ'},
        'en-us': {'name': 'Scatology'},
      },
      count: 21,
    ),
    Tag(
      id: 15,
      name: '严肃/沉重',
      i18n: {
        'zh-cn': {'name': '严肃/沉重'},
        'ja-jp': {'name': 'シリアス'},
        'en-us': {'name': 'Serious'},
      },
      count: 20,
    ),
    Tag(
      id: 126,
      name: '外射',
      i18n: {
        'zh-cn': {'name': '外射'},
        'ja-jp': {'name': 'ぶっかけ'},
        'en-us': {'name': 'Bukkake'},
      },
      count: 20,
    ),
    Tag(
      id: 661,
      name: '常识改变',
      i18n: {
        'zh-cn': {'name': '常识改变'},
        'ja-jp': {'name': '常識改変'},
        'en-us': {'name': 'Altered Sense of Normal'},
      },
      count: 20,
    ),
    Tag(
      id: 171,
      name: '黑发',
      i18n: {
        'zh-cn': {'name': '黑发'},
        'ja-jp': {'name': '黒髪'},
        'en-us': {'name': 'Black Hair'},
      },
      count: 19,
    ),
    Tag(
      id: 531,
      name: '萝莉老太婆',
      i18n: {
        'zh-cn': {'name': '萝莉老太婆'},
        'ja-jp': {'name': 'ロリババア'},
        'en-us': {'name': 'Lolibaba'},
      },
      count: 18,
    ),
    Tag(
      id: 519,
      name: '异世界转生',
      i18n: {
        'zh-cn': {'name': '异世界转生'},
        'ja-jp': {'name': '異世界転生'},
        'en-us': {'name': 'Isekai'},
      },
      count: 18,
    ),
    Tag(
      id: 639,
      name: '助眠',
      i18n: {
        'zh-cn': {'name': '助眠'},
        'ja-jp': {'name': '睡眠導入'},
        'en-us': {'name': 'Sleep Induction'},
      },
      count: 18,
    ),
    Tag(
      id: 507,
      name: '技术书',
      i18n: {
        'zh-cn': {'name': '技术书'},
        'ja-jp': {'name': '技術書'},
        'en-us': {'name': 'Technical Book'},
      },
      count: 18,
    ),
    Tag(
      id: 147,
      name: '奴隶',
      i18n: {
        'zh-cn': {'name': '奴隶'},
        'ja-jp': {'name': '奴隷'},
        'en-us': {'name': 'Slave'},
      },
      count: 18,
    ),
    Tag(
      id: 154,
      name: '鬼畜',
      i18n: {
        'zh-cn': {'name': '鬼畜'},
        'ja-jp': {'name': '鬼畜'},
        'en-us': {'name': 'Fiendish / Brutal'},
      },
      count: 18,
    ),
    Tag(
      id: 641,
      name: '打嗝',
      i18n: {
        'zh-cn': {'name': '打嗝'},
        'ja-jp': {'name': 'ゲップ'},
        'en-us': {'name': 'Burping'},
      },
      count: 18,
    ),
    Tag(
      id: 83,
      name: '内裤',
      i18n: {
        'zh-cn': {'name': '内裤'},
        'ja-jp': {'name': 'パンツ'},
        'en-us': {'name': 'Panties'},
      },
      count: 17,
    ),
    Tag(
      id: 28,
      name: '年龄差',
      i18n: {
        'zh-cn': {'name': '年龄差'},
        'ja-jp': {'name': '歳の差'},
        'en-us': {'name': 'Age Disparity'},
      },
      count: 17,
    ),
    Tag(
      id: 301,
      name: '电车',
      i18n: {
        'zh-cn': {'name': '电车'},
        'ja-jp': {'name': '電車'},
        'en-us': {'name': 'Train'},
      },
      count: 17,
    ),
    Tag(
      id: 411,
      name: '体育系/运动员',
      i18n: {
        'zh-cn': {'name': '体育系/运动员'},
        'ja-jp': {'name': '体育会系/スポーツ選手'},
        'en-us': {'name': 'Jock / Athlete / Sports'},
      },
      count: 17,
    ),
    Tag(
      id: 177,
      name: '高挑',
      i18n: {
        'zh-cn': {'name': '高挑'},
        'ja-jp': {'name': '長身'},
        'en-us': {'name': 'Tall Person'},
      },
      count: 17,
    ),
    Tag(
      id: 196,
      name: '方言',
      i18n: {
        'zh-cn': {'name': '方言'},
        'ja-jp': {'name': '方言'},
        'en-us': {'name': 'Dialect (Language)'},
      },
      count: 16,
    ),
    Tag(
      id: 112,
      name: '正常玩法',
      i18n: {
        'zh-cn': {'name': '正常玩法'},
        'ja-jp': {'name': 'ノーマルプレイ'},
        'en-us': {'name': 'Vanilla Sex'},
      },
      count: 16,
    ),
    Tag(
      id: 257,
      name: '道具/异物',
      i18n: {
        'zh-cn': {'name': '道具/异物'},
        'ja-jp': {'name': '道具/異物'},
        'en-us': {'name': 'Foreign Objects'},
      },
      count: 15,
    ),
    Tag(
      id: 167,
      name: '长发',
      i18n: {
        'zh-cn': {'name': '长发'},
        'ja-jp': {'name': 'ロングヘア'},
        'en-us': {'name': 'Long Hair'},
      },
      count: 15,
    ),
    Tag(
      id: 241,
      name: '魔法师/魔女',
      i18n: {
        'zh-cn': {'name': '魔法师/魔女'},
        'ja-jp': {'name': '魔法使い/魔女'},
        'en-us': {'name': 'Magician / Witch'},
      },
      count: 15,
    ),
    Tag(
      id: 644,
      name: 'BSS/暗恋被抢',
      i18n: {
        'zh-cn': {'name': 'BSS/暗恋被抢'},
        'ja-jp': {'name': 'BSS'},
        'en-us': {'name': 'BSS / Thwarted Love'},
      },
      count: 15,
    ),
    Tag(
      id: 227,
      name: '教师',
      i18n: {
        'zh-cn': {'name': '教师'},
        'ja-jp': {'name': '教師'},
        'en-us': {'name': 'Teacher'},
      },
      count: 14,
    ),
    Tag(
      id: 541,
      name: '兽人',
      i18n: {
        'zh-cn': {'name': '兽人'},
        'ja-jp': {'name': '獣人'},
        'en-us': {'name': 'Beastkin'},
      },
      count: 14,
    ),
    Tag(
      id: 214,
      name: '义妹',
      i18n: {
        'zh-cn': {'name': '义妹'},
        'ja-jp': {'name': '義妹'},
        'en-us': {'name': 'Younger Stepsister'},
      },
      count: 14,
    ),
    Tag(
      id: 288,
      name: '主从/主仆',
      i18n: {
        'zh-cn': {'name': '主从/主仆'},
        'ja-jp': {'name': '主従'},
        'en-us': {'name': 'Master and Servant'},
      },
      count: 14,
    ),
    Tag(
      id: 505,
      name: '女忍者',
      i18n: {
        'zh-cn': {'name': '女忍者'},
        'ja-jp': {'name': 'くノ一'},
        'en-us': {'name': 'Kunoichi (Ninja Girl)'},
      },
      count: 14,
    ),
    Tag(
      id: 295,
      name: '软色情',
      i18n: {
        'zh-cn': {'name': '软色情'},
        'ja-jp': {'name': 'ソフトエッチ'},
        'en-us': {'name': 'Softcore Eroticism'},
      },
      count: 14,
    ),
    Tag(
      id: 313,
      name: '虐待/ryona',
      i18n: {
        'zh-cn': {'name': '虐待/ryona'},
        'ja-jp': {'name': 'リョナ'},
        'en-us': {'name': 'Ryona / Brutal'},
      },
      count: 14,
    ),
    Tag(
      id: 175,
      name: '猫耳',
      i18n: {
        'zh-cn': {'name': '猫耳'},
        'ja-jp': {'name': 'ネコミミ'},
        'en-us': {'name': 'Nekomimi (Cat Ears)'},
      },
      count: 13,
    ),
    Tag(
      id: 211,
      name: '正太',
      i18n: {
        'zh-cn': {'name': '正太'},
        'ja-jp': {'name': 'ショタ'},
        'en-us': {'name': 'Shota'},
      },
      count: 13,
    ),
    Tag(
      id: 205,
      name: '疯狂',
      i18n: {
        'zh-cn': {'name': '疯狂'},
        'ja-jp': {'name': '狂気'},
        'en-us': {'name': 'Madness'},
      },
      count: 13,
    ),
    Tag(
      id: 539,
      name: '体型差',
      i18n: {
        'zh-cn': {'name': '体型差'},
        'ja-jp': {'name': '体格差'},
        'en-us': {'name': 'Body Size Disparity'},
      },
      count: 13,
    ),
    Tag(
      id: 139,
      name: '痴汉',
      i18n: {
        'zh-cn': {'name': '痴汉'},
        'ja-jp': {'name': '痴漢'},
        'en-us': {'name': 'Molestation'},
      },
      count: 12,
    ),
    Tag(
      id: 521,
      name: '执着攻',
      i18n: {
        'zh-cn': {'name': '执着攻'},
        'ja-jp': {'name': '執着攻め'},
        'en-us': {'name': 'Clingy (Dominant)'},
      },
      count: 12,
    ),
    Tag(
      id: 104,
      name: '死库水/校园泳装',
      i18n: {
        'zh-cn': {'name': '死库水/校园泳装'},
        'ja-jp': {'name': 'スクール水着'},
        'en-us': {'name': 'School Swimwear'},
      },
      count: 12,
    ),
    Tag(
      id: 534,
      name: '正太×姐姐',
      i18n: {
        'zh-cn': {'name': '正太×姐姐'},
        'ja-jp': {'name': 'ショタおね'},
        'en-us': {'name': 'Younger Boy x Elder Girl'},
      },
      count: 12,
    ),
    Tag(
      id: 303,
      name: '伪娘',
      i18n: {
        'zh-cn': {'name': '伪娘'},
        'ja-jp': {'name': '男の娘'},
        'en-us': {'name': 'Otoko no ko'},
      },
      count: 12,
    ),
    Tag(
      id: 7,
      name: '喜剧',
      i18n: {
        'zh-cn': {'name': '喜剧'},
        'ja-jp': {'name': 'コメディ'},
        'en-us': {'name': 'Comedy'},
      },
      count: 11,
    ),
    Tag(
      id: 174,
      name: '双马尾',
      i18n: {
        'zh-cn': {'name': '双马尾'},
        'ja-jp': {'name': 'ツインテール'},
        'en-us': {'name': 'Twin Tail'},
      },
      count: 11,
    ),
    Tag(
      id: 251,
      name: '野兽/兽化',
      i18n: {
        'zh-cn': {'name': '野兽/兽化'},
        'ja-jp': {'name': 'けもの/獣化'},
        'en-us': {'name': 'Kemo / Animalization / Transfur'},
      },
      count: 11,
    ),
    Tag(
      id: 77,
      name: '泳装',
      i18n: {
        'zh-cn': {'name': '泳装'},
        'ja-jp': {'name': '水着'},
        'en-us': {'name': 'Swimwear'},
      },
      count: 11,
    ),
    Tag(
      id: 315,
      name: '亲姐姐',
      i18n: {
        'zh-cn': {'name': '亲姐姐'},
        'ja-jp': {'name': '実姉'},
        'en-us': {'name': 'Real Elder Sister'},
      },
      count: 11,
    ),
    Tag(
      id: 29,
      name: '魔法',
      i18n: {
        'zh-cn': {'name': '魔法'},
        'ja-jp': {'name': '魔法'},
        'en-us': {'name': 'Magic'},
      },
      count: 11,
    ),
    Tag(
      id: 55,
      name: '感动',
      i18n: {
        'zh-cn': {'name': '感动'},
        'ja-jp': {'name': '感動'},
        'en-us': {'name': 'Emotional / Touching'},
      },
      count: 11,
    ),
    Tag(
      id: 509,
      name: '3D作品',
      i18n: {
        'zh-cn': {'name': '3D作品'},
        'ja-jp': {'name': '3D作品'},
        'en-us': {'name': '3D Works'},
      },
      count: 11,
    ),
    Tag(
      id: 226,
      name: '女教师',
      i18n: {
        'zh-cn': {'name': '女教师'},
        'ja-jp': {'name': '女教師'},
        'en-us': {'name': 'Female Teacher'},
      },
      count: 11,
    ),
    Tag(
      id: 645,
      name: '换偶',
      i18n: {
        'zh-cn': {'name': '换偶'},
        'ja-jp': {'name': 'スワッピング'},
        'en-us': {'name': 'Partner Swapping'},
      },
      count: 11,
    ),
    Tag(
      id: 419,
      name: '不良/混混',
      i18n: {
        'zh-cn': {'name': '不良/混混'},
        'ja-jp': {'name': '不良/ヤンキー'},
        'en-us': {'name': 'Delinquent / Hoodlum'},
      },
      count: 10,
    ),
    Tag(
      id: 166,
      name: '短发',
      i18n: {
        'zh-cn': {'name': '短发'},
        'ja-jp': {'name': 'ショートカット'},
        'en-us': {'name': 'Short Hair'},
      },
      count: 10,
    ),
    Tag(
      id: 484,
      name: '腹击',
      i18n: {
        'zh-cn': {'name': '腹击'},
        'ja-jp': {'name': '腹パン'},
        'en-us': {'name': 'Gut Punch'},
      },
      count: 9,
    ),
    Tag(
      id: 246,
      name: '天然呆',
      i18n: {
        'zh-cn': {'name': '天然呆'},
        'ja-jp': {'name': '天然'},
        'en-us': {'name': 'Natural Airhead'},
      },
      count: 9,
    ),
    Tag(
      id: 216,
      name: '义母',
      i18n: {
        'zh-cn': {'name': '义母'},
        'ja-jp': {'name': '義母'},
        'en-us': {'name': 'Stepmother'},
      },
      count: 9,
    ),
    Tag(
      id: 424,
      name: '上司',
      i18n: {
        'zh-cn': {'name': '上司'},
        'ja-jp': {'name': '上司'},
        'en-us': {'name': 'Boss'},
      },
      count: 8,
    ),
    Tag(
      id: 62,
      name: '腿/足',
      i18n: {
        'zh-cn': {'name': '腿/足'},
        'ja-jp': {'name': '脚'},
        'en-us': {'name': 'Legs'},
      },
      count: 8,
    ),
    Tag(
      id: 311,
      name: '触摸/抚摸',
      i18n: {
        'zh-cn': {'name': '触摸/抚摸'},
        'ja-jp': {'name': 'おさわり'},
        'en-us': {'name': 'Touch / Feel'},
      },
      count: 8,
    ),
    Tag(
      id: 255,
      name: '眼镜',
      i18n: {
        'zh-cn': {'name': '眼镜'},
        'ja-jp': {'name': 'メガネ'},
        'en-us': {'name': 'Glasses'},
      },
      count: 8,
    ),
    Tag(
      id: 75,
      name: '水手服',
      i18n: {
        'zh-cn': {'name': '水手服'},
        'ja-jp': {'name': 'セーラー服'},
        'en-us': {'name': 'Sailor-style Uniform'},
      },
      count: 8,
    ),
    Tag(
      id: 463,
      name: '双性恋',
      i18n: {
        'zh-cn': {'name': '双性恋'},
        'ja-jp': {'name': 'バイ'},
        'en-us': {'name': 'Bisexual'},
      },
      count: 8,
    ),
    Tag(
      id: 153,
      name: '挠痒痒',
      i18n: {
        'zh-cn': {'name': '挠痒痒'},
        'ja-jp': {'name': 'くすぐり'},
        'en-us': {'name': 'Tickling'},
      },
      count: 8,
    ),
    Tag(
      id: 49,
      name: '着衣/穿衣',
      i18n: {
        'zh-cn': {'name': '着衣/穿衣'},
        'ja-jp': {'name': '着衣'},
        'en-us': {'name': 'Clothed'},
      },
      count: 8,
    ),
    Tag(
      id: 293,
      name: '管家/执事',
      i18n: {
        'zh-cn': {'name': '管家/执事'},
        'ja-jp': {'name': '執事'},
        'en-us': {'name': 'Butler'},
      },
      count: 8,
    ),
    Tag(
      id: 31,
      name: '同居',
      i18n: {
        'zh-cn': {'name': '同居'},
        'ja-jp': {'name': '同居'},
        'en-us': {'name': 'Living Together'},
      },
      count: 8,
    ),
    Tag(
      id: 188,
      name: '白虎/无阴毛',
      i18n: {
        'zh-cn': {'name': '白虎/无阴毛'},
        'ja-jp': {'name': 'パイパン'},
        'en-us': {'name': 'No Pubic Hair'},
      },
      count: 7,
    ),
    Tag(
      id: 284,
      name: '警察/刑警',
      i18n: {
        'zh-cn': {'name': '警察/刑警'},
        'ja-jp': {'name': '警察/刑事'},
        'en-us': {'name': 'Police / Detective'},
      },
      count: 7,
    ),
    Tag(
      id: 243,
      name: '妖怪',
      i18n: {
        'zh-cn': {'name': '妖怪'},
        'ja-jp': {'name': '妖怪'},
        'en-us': {'name': 'Youkai'},
      },
      count: 7,
    ),
    Tag(
      id: 494,
      name: '浪漫',
      i18n: {
        'zh-cn': {'name': '浪漫'},
        'ja-jp': {'name': 'ロマンス'},
        'en-us': {'name': 'Romance'},
      },
      count: 7,
    ),
    Tag(
      id: 423,
      name: '叔父/义父',
      i18n: {
        'zh-cn': {'name': '叔父/义父'},
        'ja-jp': {'name': '叔父/義父'},
        'en-us': {'name': 'Uncle / Stepfather'},
      },
      count: 7,
    ),
    Tag(
      id: 651,
      name: '敬语',
      i18n: {
        'zh-cn': {'name': '敬语'},
        'ja-jp': {'name': '敬語'},
        'en-us': {'name': 'Formal Speech'},
      },
      count: 7,
    ),
    Tag(
      id: 82,
      name: '内衣',
      i18n: {
        'zh-cn': {'name': '内衣'},
        'ja-jp': {'name': '下着'},
        'en-us': {'name': 'Underwear'},
      },
      count: 7,
    ),
    Tag(
      id: 10,
      name: '科幻',
      i18n: {
        'zh-cn': {'name': '科幻'},
        'ja-jp': {'name': 'SF'},
        'en-us': {'name': 'SF'},
      },
      count: 7,
    ),
    Tag(
      id: 137,
      name: '捆绑/紧缚',
      i18n: {
        'zh-cn': {'name': '捆绑/紧缚'},
        'ja-jp': {'name': '緊縛'},
        'en-us': {'name': 'Sexual Bondage'},
      },
      count: 7,
    ),
    Tag(
      id: 5,
      name: '搞笑',
      i18n: {
        'zh-cn': {'name': '搞笑'},
        'ja-jp': {'name': 'ギャグ'},
        'en-us': {'name': 'Gag / Joke'},
      },
      count: 6,
    ),
    Tag(
      id: 322,
      name: '包茎',
      i18n: {
        'zh-cn': {'name': '包茎'},
        'ja-jp': {'name': '包茎'},
        'en-us': {'name': 'Phimosis'},
      },
      count: 6,
    ),
    Tag(
      id: 100,
      name: '紧身裤/运动短裤',
      i18n: {
        'zh-cn': {'name': '紧身裤/运动短裤'},
        'ja-jp': {'name': 'スパッツ'},
        'en-us': {'name': 'Leggings'},
      },
      count: 6,
    ),
    Tag(
      id: 486,
      name: '寡妇',
      i18n: {
        'zh-cn': {'name': '寡妇'},
        'ja-jp': {'name': '未亡人'},
        'en-us': {'name': 'Widow'},
      },
      count: 6,
    ),
  ];

  /// 按 id 快速查找。
  static Tag? byId(int id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 关键字过滤（同时匹配中 / 日 / 英文名）。
  static List<Tag> search(String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return all;
    return all
        .where(
          (t) =>
              t.label(AppLang.zh).toLowerCase().contains(k) ||
              t.label(AppLang.ja).toLowerCase().contains(k) ||
              t.label(AppLang.en).toLowerCase().contains(k),
        )
        .toList();
  }
}
