const upstreamRepository = 'chen08209/FlClash';
const penrixPrivateRepository = 'Penrix/FlClash';

const isPenrixPrivateBuild = bool.fromEnvironment('PENRIX_PRIVATE_BUILD');
const penrixPrivateRunNumber = int.fromEnvironment('PENRIX_PRIVATE_RUN_NUMBER');
const penrixPrivateRunAttempt = int.fromEnvironment(
  'PENRIX_PRIVATE_RUN_ATTEMPT',
);

const repository = isPenrixPrivateBuild
    ? penrixPrivateRepository
    : upstreamRepository;

final RegExp _penrixPrivateTagPattern = RegExp(
  r'^penrix-private-windows-r(\d+)-a(\d+)$',
);

class PenrixPrivateReleaseId implements Comparable<PenrixPrivateReleaseId> {
  final int runNumber;
  final int runAttempt;

  const PenrixPrivateReleaseId(this.runNumber, this.runAttempt);

  static PenrixPrivateReleaseId? tryParse(String? tag) {
    if (tag == null) return null;
    final match = _penrixPrivateTagPattern.firstMatch(tag);
    if (match == null) return null;
    return PenrixPrivateReleaseId(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  @override
  int compareTo(PenrixPrivateReleaseId other) {
    final runComparison = runNumber.compareTo(other.runNumber);
    if (runComparison != 0) return runComparison;
    return runAttempt.compareTo(other.runAttempt);
  }
}

Map<String, dynamic>? selectPenrixPrivateUpdate(
  Iterable<dynamic> releases, {
  required int currentRunNumber,
  required int currentRunAttempt,
}) {
  final current = PenrixPrivateReleaseId(currentRunNumber, currentRunAttempt);
  Map<String, dynamic>? selected;
  PenrixPrivateReleaseId? selectedId;

  for (final rawRelease in releases) {
    if (rawRelease is! Map) continue;
    final release = rawRelease.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (release['draft'] == true || release['prerelease'] != true) continue;
    final id = PenrixPrivateReleaseId.tryParse(release['tag_name']?.toString());
    if (id == null || id.compareTo(current) <= 0) continue;
    if (selectedId == null || id.compareTo(selectedId) > 0) {
      selected = release;
      selectedId = id;
    }
  }
  return selected;
}

String buildDisplayVersion(
  String version, {
  bool privateBuild = isPenrixPrivateBuild,
  int runNumber = penrixPrivateRunNumber,
  int runAttempt = penrixPrivateRunAttempt,
}) {
  if (!privateBuild) return version;
  if (runNumber <= 0 || runAttempt <= 0) {
    return '$version · Penrix Private dev';
  }
  return '$version · Penrix Private r$runNumber-a$runAttempt';
}

String releasePageUrl(Map<String, dynamic> release) {
  final url = release['html_url']?.toString().trim();
  if (url != null && url.isNotEmpty) return url;
  return 'https://github.com/$repository/releases';
}
