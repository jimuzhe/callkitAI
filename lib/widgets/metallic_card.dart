import 'package:flutter/material.dart';

/// 金属质感卡片 - 统一的金属光泽效果
class MetallicCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated; // 是否使用凸起效果
  final double? height;

  const MetallicCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
    this.elevated = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF4B5563),
                  const Color(0xFF374151),
                  const Color(0xFF3F4654),
                  const Color(0xFF2D3748),
                ]
              : [
                  const Color(0xFFE8E8E8),
                  const Color(0xFFD1D5DB),
                  const Color(0xFFDCDCDC),
                  const Color(0xFFC0C0C0),
                ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          // 高光
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.9),
            offset: const Offset(-2, -2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
          // 阴影
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
            offset: const Offset(2, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.15 : 0.4),
                  Colors.transparent,
                  Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 金属质感按钮
class MetallicButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isExtended;
  final IconData? icon;

  const MetallicButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isExtended = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF6B7280), const Color(0xFF4B5563)]
              : [const Color(0xFFD1D5DB), const Color(0xFFA8A8A8)],
        ),
        borderRadius: BorderRadius.circular(isExtended ? 16 : 28),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.7),
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(isExtended ? 16 : 28),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(isExtended ? 16 : 28),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isExtended ? 24 : 16,
              vertical: isExtended ? 16 : 16,
            ),
            child: Row(
              mainAxisSize: isExtended ? MainAxisSize.min : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: isDark
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF1F2937),
                  ),
                  if (isExtended) const SizedBox(width: 8),
                ],
                if (isExtended)
                  DefaultTextStyle(
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF1F2937),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    child: child,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 金属质感文字 - 带浮雕效果
class MetallicText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final bool isLarge; // 大号文字使用双重阴影

  const MetallicText({
    super.key,
    required this.text,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w600,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937),
        letterSpacing: isLarge ? -0.5 : 0.3,
        shadows: isLarge
            ? [
                Shadow(
                  color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.9),
                  offset: const Offset(0, 2),
                  blurRadius: 2,
                ),
                Shadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
                  offset: const Offset(0, -1),
                  blurRadius: 1,
                ),
              ]
            : [
                Shadow(
                  color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.7),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
      ),
    );
  }
}

/// 金属质感图标容器
class MetallicIconBox extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? iconColor;

  const MetallicIconBox({
    super.key,
    required this.icon,
    this.size = 24,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF6B7280), const Color(0xFF4B5563)]
              : [Colors.white.withValues(alpha: 0.9), Colors.grey.shade300],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
            offset: const Offset(1, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Icon(
        icon,
        color:
            iconColor ??
            (isDark ? const Color(0xFFE5E7EB) : const Color(0xFF4A5568)),
        size: size,
      ),
    );
  }
}

/// 圆形金属按钮（适合通话页的麦克风/静音/扬声器等图标按钮）
class MetallicCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final double size; // 直径
  final Color? activeColor;

  const MetallicCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.active = false,
    this.size = 56,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final diameter = size;
    final radius = diameter / 2;

    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [const Color(0xFF6B7280), const Color(0xFF4B5563)]
          : [const Color(0xFFD1D5DB), const Color(0xFFA8A8A8)],
    );

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: baseGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.6),
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.25),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.12 : 0.4),
                  Colors.transparent,
                  Colors.black.withValues(alpha: isDark ? 0.18 : 0.1),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              border: active
                  ? Border.all(
                      color:
                          activeColor ?? Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: Center(
              child: Icon(
                icon,
                color: active
                    ? (activeColor ?? Theme.of(context).colorScheme.primary)
                    : (isDark
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF1F2937)),
                size: radius,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
