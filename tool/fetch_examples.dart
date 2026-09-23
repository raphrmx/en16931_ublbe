// Downloads the test cases UBL.BE publishes.
//
// UBL.BE publishes them at https://www.ubl.be/version-information/ as a zip
// per release, carried verbatim by the phive-rules project at
// https://github.com/phax/phive-rules. They carry no licence, so they are
// read by the test suite and never redistributed: they land in a directory
// git ignores.
//
// The rules are pinned to a release; the test cases are read from the mirror's
// master on purpose, taking the newest release it holds. A release that
// changes what a valid UBL.BE invoice looks like then turns the build red
// here, before anyone raises the pin.
//
// Usage:
//   dart run tool/fetch_examples.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const String _tree =
    'https://api.github.com/repos/phax/phive-rules/git/trees/master'
    '?recursive=1';

const String _raw = 'https://raw.githubusercontent.com/phax/phive-rules/master';

const String _folder = 'phive-rules-ublbe/docs/';

const String _directory = 'examples_from_ublbe';

/// A test case zip, capturing the release it is for.
final RegExp _testCases = RegExp(r'Testcases[ -]UBLBE[ -]V(\d+)\.(\d+)\.zip$');

Future<void> main() async {
  final client = HttpClient();
  try {
    final listing = jsonDecode(utf8.decode(await _bytes(client, _tree))) as Map;
    final zips = [
      for (final entry in listing['tree'] as List)
        if ((entry as Map)['path'] case final String path
            when path.startsWith(_folder) && _testCases.hasMatch(path))
          path,
    ]..sort((a, b) => _release(a).compareTo(_release(b)));
    if (zips.isEmpty) {
      throw StateError('The mirror no longer holds UBL.BE test cases.');
    }
    final newest = zips.last;
    final archive = ZipDecoder().decodeBytes(
      await _bytes(client, '$_raw/${Uri.encodeFull(newest)}'),
    );

    final directory = Directory(_directory);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
    var count = 0;
    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.xml')) continue;
      File(
        '$_directory/${file.name.split('/').last}',
      ).writeAsBytesSync(file.content);
      count++;
    }
    stdout.writeln('$count documents in $_directory, from $newest');
  } finally {
    client.close();
  }
}

/// The release a zip is for, as a number that sorts: V1.31 is 1031.
int _release(String path) {
  final match = _testCases.firstMatch(path)!;
  return int.parse(match.group(1)!) * 1000 + int.parse(match.group(2)!);
}

Future<List<int>> _bytes(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', 'en16931_ublbe');
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token != null && token.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} for $url');
  }
  final bytes = <int>[];
  await response.forEach(bytes.addAll);
  return bytes;
}
