import 'package:flutter/material.dart';

/// Pull down to refresh, the same on every list in the app (like Chrome).
/// Give a real [onRefresh] where there is something to reload; otherwise it
/// just shows the refresh spinner briefly so the gesture always answers.
class PullRefresh extends StatelessWidget {
  final Future<void> Function()? onRefresh;
  final Widget child;
  const PullRefresh({super.key, this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh ??
            () => Future<void>.delayed(const Duration(milliseconds: 450)),
        child: child,
      );
}

/// Lets a short list be pulled too (a list that fits the screen would not
/// scroll, so it would never start a refresh).
const ScrollPhysics kPullPhysics = AlwaysScrollableScrollPhysics();
