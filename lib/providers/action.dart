import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/common.dart' hide makeRealProfileTask;
import 'package:fl_clash/common/penrix_private.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/common/task.dart' as upstream_task;
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/actions/system_exit.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show basename;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Private-build profile compiler.
///
/// Keep upstream profile generation intact, but always place the private
/// application/site routing layer on top of whatever subscription is active.
/// PROCESS-NAME rules require process matching, so the private build forces it
/// on instead of depending on a profile or a forgotten UI toggle.
Future<({String yaml, String md5})> makeRealProfileTask(
  MakeRealProfileState data,
) {
  final privateConfig = buildPenrixPrivateNetworkConfig(data.rawConfig);
  return upstream_task.makeRealProfileTask(
    data.copyWith(
      rawConfig: privateConfig,
      realPatchConfig: data.realPatchConfig.copyWith(
        findProcessMode: FindProcessMode.always,
      ),
    ),
  );
}

part 'actions/common.dart';
part 'actions/setup.dart';
part 'actions/backup.dart';
part 'actions/core.dart';
part 'actions/system.dart';
part 'actions/store.dart';
part 'actions/theme.dart';
part 'actions/proxies.dart';
part 'actions/profiles.dart';
part 'actions/geo_resource.dart';
part 'actions/updating.dart';
part 'generated/action.g.dart';