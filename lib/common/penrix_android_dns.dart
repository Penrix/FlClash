/// Android's native VPN/TUN path owns device DNS interception. Exposing an
/// additional Mihomo DNS listener from a subscription is unnecessary there and
/// can collide with another installed/running FlClash build (for example both
/// trying to bind 0.0.0.0:7874).
///
/// The final profile has already been normalized by FlClash's YAML encoder, so
/// this removes only the direct `listen` child of the top-level `dns` mapping.
/// Other DNS behavior (nameserver, fake-ip, policies, fallback, etc.) is kept.
String stripExternalDnsListenFromYaml(String source) {
  final lines = source.split('\n');
  final output = <String>[];
  var inTopLevelDns = false;
  int? childIndent;

  for (final line in lines) {
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;

    if (!inTopLevelDns) {
      if (indent == 0 && trimmed == 'dns:') {
        inTopLevelDns = true;
        childIndent = null;
      }
      output.add(line);
      continue;
    }

    if (trimmed.isNotEmpty && indent == 0) {
      inTopLevelDns = false;
      childIndent = null;
      output.add(line);
      continue;
    }

    if (trimmed.isEmpty) {
      output.add(line);
      continue;
    }

    childIndent ??= indent;
    if (indent == childIndent && trimmed.startsWith('listen:')) {
      continue;
    }
    output.add(line);
  }

  return output.join('\n');
}
