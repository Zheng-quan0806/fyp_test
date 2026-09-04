import 'package:flutter/material.dart';

import '../services/study_streak_service.dart';

class StudyActivityRegion extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const StudyActivityRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<StudyActivityRegion> createState() => _StudyActivityRegionState();
}

class _StudyActivityRegionState extends State<StudyActivityRegion> {
  final Object _region = Object();

  @override
  void initState() {
    super.initState();
    StudyStreakService.instance.setRegionActive(_region, widget.enabled);
  }

  @override
  void didUpdateWidget(covariant StudyActivityRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      StudyStreakService.instance.setRegionActive(_region, widget.enabled);
    }
  }

  @override
  void dispose() {
    StudyStreakService.instance.setRegionActive(_region, false);
    super.dispose();
  }

  void _activity([PointerEvent? _]) =>
      StudyStreakService.instance.registerInteraction();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _activity,
      onPointerMove: _activity,
      onPointerSignal: _activity,
      child: MouseRegion(onHover: _activity, child: widget.child),
    );
  }
}
