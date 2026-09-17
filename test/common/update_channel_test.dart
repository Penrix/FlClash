import 'package:fl_clash/common/update_channel.dart';
import 'package:test/test.dart';

void main() {
  group('Penrix private update channel', () {
    test('parses and compares private release identities', () {
      final first = PenrixPrivateReleaseId.tryParse(
        'penrix-private-windows-r12-a1',
      );
      final retry = PenrixPrivateReleaseId.tryParse(
        'penrix-private-windows-r12-a2',
      );

      expect(first, isNotNull);
      expect(retry, isNotNull);
      expect(retry!.compareTo(first!), greaterThan(0));
      expect(PenrixPrivateReleaseId.tryParse('v0.8.98'), isNull);
    });

    test('selects the newest eligible private prerelease', () {
      final selected = selectPenrixPrivateUpdate(
        [
          {
            'tag_name': 'penrix-private-windows-r20-a1',
            'prerelease': true,
            'draft': false,
          },
          {
            'tag_name': 'penrix-private-windows-r21-a1',
            'prerelease': true,
            'draft': true,
          },
          {
            'tag_name': 'penrix-private-windows-r20-a2',
            'prerelease': true,
            'draft': false,
          },
          {'tag_name': 'v99.0.0', 'prerelease': false, 'draft': false},
        ],
        currentRunNumber: 19,
        currentRunAttempt: 1,
      );

      expect(selected?['tag_name'], 'penrix-private-windows-r20-a2');
    });

    test('does not return the current or an older private release', () {
      final selected = selectPenrixPrivateUpdate(
        [
          {
            'tag_name': 'penrix-private-windows-r20-a1',
            'prerelease': true,
            'draft': false,
          },
          {
            'tag_name': 'penrix-private-windows-r19-a9',
            'prerelease': true,
            'draft': false,
          },
        ],
        currentRunNumber: 20,
        currentRunAttempt: 1,
      );

      expect(selected, isNull);
    });

    test('keeps official version text and labels private builds', () {
      expect(
        buildDisplayVersion('0.8.98', privateBuild: false),
        '0.8.98',
      );
      expect(
        buildDisplayVersion(
          '0.8.98',
          privateBuild: true,
          runNumber: 42,
          runAttempt: 3,
        ),
        '0.8.98 · Penrix Private r42-a3',
      );
    });

    test('uses the selected release page for download', () {
      expect(
        releasePageUrl({
          'html_url':
              'https://github.com/Penrix/FlClash/releases/tag/'
              'penrix-private-windows-r42-a3',
        }),
        endsWith('penrix-private-windows-r42-a3'),
      );
    });
  });
}
