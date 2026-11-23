import 'package:flutter/material.dart';

/// Provides touch feedback while Home destinations remain presentational.
class HomeAction extends StatelessWidget {
  const HomeAction({
    required this.child,
    this.decoration,
    this.onTap,
    this.footer,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BoxDecoration? decoration;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final Widget action = InkWell(
      onTap: onTap ?? () {},
      borderRadius:
          decoration?.borderRadius?.resolve(Directionality.of(context)) ??
          BorderRadius.circular(8),
      child: child,
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: footer == null
            ? action
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(child: action),
                  footer!,
                ],
              ),
      ),
    );
  }
}
