import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 主题构建器。
///
/// 设计取向：Material 3 + 深色优先，圆角偏大、留白充足，
/// 列表以封面为主体，弱化分割线，用色阶而非边框区分层级。
class AppTheme {
  const AppTheme._();

  /// 可选强调色（设置页里的色板）。
  static const List<Color> accentChoices = [
    Color(0xFF7C5CFF), // 紫罗兰（默认）
    Color(0xFFFF6FB5), // 樱花粉
    Color(0xFF4FC3F7), // 天空蓝
    Color(0xFF3DDC97), // 薄荷绿
    Color(0xFFFFA85C), // 琥珀橙
    Color(0xFFFF5F6D), // 珊瑚红
    Color(0xFFB388FF), // 淡紫
    Color(0xFF64B5F6), // 靛蓝
  ];

  static const Color _darkBg = Color(0xFF0B0910);
  static const Color _darkSurface = Color(0xFF15121C);
  static const Color _lightBg = Color(0xFFF6F5FA);

  static ThemeData build({
    required Brightness brightness,
    required Color seed,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          surface: brightness == Brightness.dark ? _darkSurface : Colors.white,
          surfaceContainerLowest: brightness == Brightness.dark
              ? const Color(0xFF0E0C14)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: brightness == Brightness.dark
              ? const Color(0xFF130F1A)
              : const Color(0xFFFAF9FE),
          surfaceContainer: brightness == Brightness.dark
              ? const Color(0xFF1A1622)
              : const Color(0xFFF2F0F9),
          surfaceContainerHigh: brightness == Brightness.dark
              ? const Color(0xFF221D2C)
              : const Color(0xFFEAE7F3),
          surfaceContainerHighest: brightness == Brightness.dark
              ? const Color(0xFF2A2436)
              : const Color(0xFFE1DDEE),
          outlineVariant: brightness == Brightness.dark
              ? const Color(0xFF322B40)
              : const Color(0xFFD9D4E4),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? _darkBg
          : _lightBg,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final text = _textTheme(base.textTheme, brightness);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary.withValues(alpha: 0.9),
        disabledColor: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: text.bodySmall,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Brightness brightness) {
    final onSurface = brightness == Brightness.dark
        ? const Color(0xFFF1EEF7)
        : const Color(0xFF1A1622);
    final variant = brightness == Brightness.dark
        ? const Color(0xFFA9A2BC)
        : const Color(0xFF6B6480);
    return base
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          fontFamilyFallback: const [
            'Noto Sans CJK SC',
            'Noto Sans SC',
            'Microsoft YaHei',
            'Source Han Sans SC',
            'PingFang SC',
          ],
        )
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: onSurface,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: onSurface,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          bodyMedium: base.bodyMedium?.copyWith(color: onSurface),
          bodySmall: base.bodySmall?.copyWith(color: variant),
          labelMedium: base.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: variant,
          ),
          labelSmall: base.labelSmall?.copyWith(color: variant),
        );
  }
}

/// 界面里复用的一些装饰常量与构建函数。
class AppDecor {
  const AppDecor._();

  static const double radiusCard = 20;
  static const double radiusSheet = 28;

  /// 主色系渐变，用于首页头部与播放器背景。
  static LinearGradient heroGradient(ColorScheme scheme) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      scheme.primary.withValues(alpha: 0.85),
      Color.lerp(
        scheme.primary,
        scheme.tertiary,
        0.55,
      )!.withValues(alpha: 0.75),
      scheme.surface.withValues(alpha: 0.0),
    ],
    stops: const [0.0, 0.55, 1.0],
  );

  /// 封面占位渐变，在图片加载完成前显示。
  static LinearGradient placeholderGradient(ColorScheme scheme, int seedId) {
    final hue = (seedId * 37) % 360;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.62).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 48) % 360, 0.42, 0.48).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c1, c2],
    );
  }

  static List<BoxShadow> softShadow(Brightness brightness) =>
      brightness == Brightness.dark
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];
}
