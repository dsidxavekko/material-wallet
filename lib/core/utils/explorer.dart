import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'feedback.dart';

/// Opens [url] in the platform browser (or a new tab on the web).
///
/// Used for "view on explorer" links so transactions and addresses can be
/// inspected on the real chain.
Future<void> openExplorer(BuildContext context, String url) async {
  final Uri uri = Uri.parse(url);
  bool launched = false;

  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    launched = false;
  }

  if (!launched && context.mounted) {
    showAppSnackBar(
      context,
      'Could not open the block explorer.',
      icon: Icons.link_off_rounded,
    );
  }
}
