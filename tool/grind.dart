import 'dart:convert';
import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:fvm/src/utils/http.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

import '../test/testing_helpers/prepare_test_environment.dart';
import 'homebrew.dart';

const _packageName = 'fvm';
const owner = 'leoafarias';
const repo = 'fvm';

void main(List<String> args) {
  pkg.name.value = _packageName;
  pkg.humanName.value = _packageName;
  pkg.githubUser.value = owner;
  pkg.githubRepo.value = 'leoafarias/fvm';
  pkg.homebrewRepo.value = 'leoafarias/homebrew-fvm';
  pkg.githubBearerToken.value = Platform.environment['GITHUB_TOKEN'];

  pkg.addAllTasks();
  addTask(homebrewTask());

  grind(args);
}

@Task('Builds the version file')
Future<void> buildVersion() async {
  final args = context.invocation.arguments;
  final versionArg = args.getOption('version');

  final pubspec = await PubSpec.load(Directory.current);
  Version? version = pubspec.version;

  if (versionArg != null) {
    version = Version.parse(versionArg);
  }

  if (version != pubspec.version) {
    var newPubSpec = pubspec.copy(version: version);
    await newPubSpec.save(Directory.current);
  }

  final versionFile = File(
    path.join(Directory.current.path, 'lib', 'src', 'version.g.dart'),
  );

  if (!versionFile.existsSync()) {
    versionFile.createSync(recursive: true);
  }

  String fileContent = '// GENERATED CODE - DO NOT MODIFY BY HAND\n\n';
  fileContent += "const packageVersion = '$version';\n";

  versionFile.writeAsStringSync(fileContent);

  log('Version $version written to version.g.dart');
}

@Task('Get all releases')
Future<void> getReleases() async {
  String owner = 'leoafarias';
  String repo = 'fvm';

  final response = await fetch(
    'https://api.github.com/repos/$owner/$repo/releases?per_page=100',
    headers: {'Accept': 'application/vnd.github.v3+json'},
  );

  final stringBuffer = StringBuffer();

  List releases = jsonDecode(response);
  for (var release in releases) {
    String tagName = release['tag_name'];
    String date = release['published_at'];
    print('Release: $tagName, Date: $date');
    stringBuffer.writeln('Release: $tagName, Date: $date');
  }

  final file = File(path.join(Directory.current.path, 'releases.txt'));

  file.writeAsStringSync(stringBuffer.toString());
}

@Task('Prepare test environment')
@Depends(buildVersion)
void testSetup() {
  final testDir = Directory(getTempTestDir());
  if (testDir.existsSync()) {
    testDir.deleteSync(recursive: true);
  }

  runDartScript('bin/main.dart', arguments: ['install', 'stable']);
}

@Task('Run tests')
@Depends(testSetup)
Future<void> test() async {
  await runAsync('dart', arguments: ['test', '--coverage=coverage']);
}

@Task('Get coverage')
Future<void> coverage() async {
  await runAsync('dart', arguments: ['pub', 'global', 'activate', 'coverage']);

  // Format coverage
  await runAsync(
    'dart',
    arguments: [
      'pub',
      'global',
      'run',
      'coverage:format_coverage',
      '--lcov',
      '--packages=.dart_tool/package_config.json',
      '--report-on=lib/',
      '--in=coverage',
      '--out=coverage/lcov.info',
    ],
  );

  // Generate html
  await runAsync(
    'genhtml',
    arguments: ['coverage/lcov.info', '-o', 'coverage/html'],
  );
}
