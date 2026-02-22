class DurationFormatter {
  /// Formats a duration as a short human-readable string (e.g. "<1m", "5m", "2h", "3d", "2mo").
  static String formatShort(Duration diff) {
    if (diff.inMinutes <= 1) return '<1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    final months = (diff.inDays / 30).round();
    return '${months}mo';
  }
}
