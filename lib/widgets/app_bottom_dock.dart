import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class AppDockItem {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool showCompletedDot;

  const AppDockItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.showCompletedDot = false,
  });
}

class AppDockButton extends StatelessWidget {
  final AppDockItem item;
  final double width;
  final double height;

  const AppDockButton({
    super.key,
    required this.item,
    this.width = 112,
    this.height = 76,
  });

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: item.isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: item.isSelected ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: item.isSelected
                  ? Colors.transparent
                  : AppTheme.border.withValues(alpha: 0.9),
            ),
            boxShadow: item.isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.highlight.withValues(alpha: 0.28),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 24,
                      color: item.isSelected
                          ? Colors.white
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: item.isSelected
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: item.isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.showCompletedDot)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.card, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if ((item.tooltip ?? '').trim().isEmpty) {
      return child;
    }

    return Tooltip(message: item.tooltip!, child: child);
  }
}

class AppDockPanel extends StatelessWidget {
  final List<AppDockItem> items;
  final EdgeInsets padding;

  const AppDockPanel({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.highlight.withValues(alpha: 0.08),
            blurRadius: 20,
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(items.length, (index) {
            return Padding(
              padding: EdgeInsets.only(
                right: index == items.length - 1 ? 0 : 10,
              ),
              child: AppDockButton(item: items[index]),
            );
          }),
        ),
      ),
    );
  }
}

class AppBottomDockLayout extends StatelessWidget {
  final Widget center;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsets padding;
  final double compactBreakpoint;
  final double sectionSpacing;
  final double sectionRunSpacing;

  const AppBottomDockLayout({
    super.key,
    required this.center,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 18),
    this.compactBreakpoint = 1180,
    this.sectionSpacing = 10,
    this.sectionRunSpacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (leading != null) leading!,
      center,
      if (trailing != null) trailing!,
    ];

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < compactBreakpoint) {
            return Wrap(
              spacing: sectionSpacing,
              runSpacing: sectionRunSpacing,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: sections,
            );
          }

          return Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(sections.length, (index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == sections.length - 1 ? 0 : sectionSpacing,
                    ),
                    child: sections[index],
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}
