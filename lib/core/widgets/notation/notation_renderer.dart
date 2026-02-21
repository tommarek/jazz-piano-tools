import 'package:flutter/material.dart';
import '../../music/pitch_class.dart';

class NotationData {
  final List<PitchClass> pitches;
  final String? label;
  final bool showKeySignature;
  final int? keySigSharps;

  const NotationData({
    required this.pitches,
    this.label,
    this.showKeySignature = false,
    this.keySigSharps,
  });
}

abstract class NotationRenderer extends StatelessWidget {
  final NotationData data;
  final double height;

  const NotationRenderer({
    super.key,
    required this.data,
    this.height = 120,
  });
}
