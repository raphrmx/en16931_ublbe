// Reads the UBL.BE rule artefact and writes the rule catalogue.
//
// UBL.BE publishes its Schematron at https://www.ubl.be/version-information/
// as a zip per release, and nowhere under version control. The zips are
// carried verbatim, release after release, by the phive-rules project at
// https://github.com/phax/phive-rules, which is where a tag can pin them. The
// bytes are checked against a digest taken when the release was adopted, so a
// mirror that changed them would stop the build rather than the catalogue.
//
// The artefact carries no licence, and the site it comes from reserves every
// right, so nothing of it is reproduced here. What is taken is which rules
// exist, how severe each is, which business terms it bears on, and the codes
// a rule compares against. Those are facts. The meaning of every rule is
// implemented by hand against the semantic model, in this package's own
// words.
//
// UBL.BE is not written as a layer over EN 16931. It is one file holding a
// copy of the standard's rules, a copy of the Peppol rules and the Belgian
// rules, edited in place: rules of the standard are commented out, dropped or
// rewritten under the same identifier. So besides the rules Belgium adds, the
// generator reads out how the copy departs from the standard this package
// validates against, and writes that down too.
//
// Usage:
//   dart run tool/generate_catalogue.dart --fetch
//   dart run tool/generate_catalogue.dart [--dump <prefix>]
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:en16931/en16931.dart';
import 'package:xml/xml.dart';

/// The release the artefact is read from.
///
/// A tag of the mirror rather than a branch, so that generating the catalogue
/// twice gives the same catalogue twice. The tag pins the mirror; [ublBeRelease]
/// says which UBL.BE release it holds, and [_digest] that it holds it
/// unchanged.
///
/// Raising this is a deliberate act: bump it, point [ublBeRelease] and
/// [_digest] at the new zip, regenerate, and read what the diff says before
/// committing it.
const String artefactRelease = 'phive-rules-parent-pom-4.6.0';

/// The UBL.BE release the pinned mirror holds.
const String ublBeRelease = 'V1.31';

/// SHA-256 of the zip UBL.BE published for [ublBeRelease].
const String _digest =
    '602823ca612f9853fc9a7a587de51c6fe690d5416a4b9f71a6bc912ecb078e5e';

const String _source =
    'https://raw.githubusercontent.com/phax/phive-rules/$artefactRelease/'
    'phive-rules-ublbe/docs/GLOBALUBL.BE%20$ublBeRelease.zip';

const String _artefact = 'artefacts/GLOBALUBL.BE.sch';

const String _output = 'lib/src/catalogue.g.dart';

/// The rule families that say how UBL is written rather than what the
/// invoice says. The copy renames the standard's UBL-CR and UBL-DT to lower
/// case; both spellings are the syntax's business.
final RegExp _syntaxFamily = RegExp('^(UBL|ubl)-(CR|DT|SR)-');

/// The rules Peppol lets one country put on its own sellers. The artefact
/// carries the ones Peppol held when it was copied; each bears only on an
/// invoice from that country, and none is Belgium's.
final RegExp _nationalFamily = RegExp('^[A-Z]{2}-[RS]-');

/// The Belgian code lists, under the names this package gives them.
const Map<String, String> _belgianLists = {
  'BTCC': 'ublBeTaxCategories',
  'BVERC': 'ublBeExemptionReasonCodes',
  'BVERCText': 'ublBeExemptionReasons',
  'BELM': 'ublBeLegalMentionCodes',
  'BELMText': 'ublBeLegalMentions',
};

/// What each Belgian list is, for the doc comment above it.
const Map<String, String> _belgianDoc = {
  'ublBeTaxCategories':
      'The Belgian VAT categories, one of which names every VAT breakdown '
      'and every invoiced item.',
  'ublBeExemptionReasonCodes':
      'The codes a VAT exemption reason (BT-121) is given under in Belgium.',
  'ublBeExemptionReasons':
      'The exact wordings a VAT exemption reason (BT-120) may take in '
      'Belgium.',
  'ublBeLegalMentionCodes':
      'The codes of the legal mentions a Belgian invoice may have to carry.',
  'ublBeLegalMentions': 'The exact wordings of those legal mentions.',
};

/// The separator each Belgian list is tokenized on in the artefact.
const Map<String, String> _separators = {
  'BTCC': ';',
  'BVERC': ';',
  'BVERCText': ';',
  'BELM': r'\s',
  'BELMText': ';',
};

/// The business terms a Belgian rule bears on, read from the UBL element it
/// tests. The Belgian messages name no business term, so the binding of the
/// element is what tells.
const Map<String, String> _elementTerms = {
  'AdditionalDocumentReference': 'BG-24',
  'DocumentDescription': 'BT-123',
  'PaymentTerms': 'BT-20',
  'TaxSubtotal': 'BG-23',
  'TaxExemptionReasonCode': 'BT-121',
  'TaxExemptionReason': 'BT-120',
  'InvoiceLine': 'BG-25',
  'ClassifiedTaxCategory': 'BG-30',
};

/// An assertion as the artefact states it.
class _Assertion {
  _Assertion(this.id, this.flag, this.context, this.test, this.terms);

  final String id;
  final String flag;
  final String context;
  final String test;
  final List<String> terms;
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--fetch')) await _fetch();

  final file = File(_artefact);
  if (!file.existsSync()) {
    stderr.writeln('Missing $_artefact. Run with --fetch.');
    exitCode = 1;
    return;
  }
  final source = file.readAsStringSync();
  final document = XmlDocument.parse(source);

  final dump = arguments.indexOf('--dump');
  if (dump != -1 && dump + 1 < arguments.length) {
    _dump(document, arguments[dump + 1]);
    return;
  }

  final assertions = _read(document);
  final standard = {for (final rule in ruleCatalogue) rule.id: rule};

  final added = [
    for (final assertion in assertions.values)
      if (!standard.containsKey(assertion.id) &&
          !_syntaxFamily.hasMatch(assertion.id) &&
          !_nationalFamily.hasMatch(assertion.id))
        assertion,
  ]..sort((a, b) => _byIdentifier(a.id, b.id));
  final national = [
    for (final id in assertions.keys)
      if (!standard.containsKey(id) && _nationalFamily.hasMatch(id)) id,
  ]..sort(_byIdentifier);
  final syntax = assertions.keys.where(_syntaxFamily.hasMatch).toList()
    ..sort(_byIdentifier);

  final commented = _commented(document);
  final suspended = [
    for (final id in standard.keys)
      if (!assertions.containsKey(id) && commented.contains(id)) id,
  ]..sort(_byIdentifier);
  final absent = [
    for (final id in standard.keys)
      if (!assertions.containsKey(id) && !commented.contains(id)) id,
  ]..sort(_byIdentifier);

  final severities = <String, String>{
    for (final assertion in assertions.values)
      if (standard[assertion.id] case final rule?)
        if (_severity(assertion.flag) != rule.severity.name)
          assertion.id: _severity(assertion.flag),
  };

  final lists = <String, Set<String>>{};
  for (final assertion in assertions.values) {
    if (!standard.containsKey(assertion.id)) continue;
    final codes = _inlineCodes(assertion.test);
    if (codes == null) continue;
    final own = codeListByRule[assertion.id];
    if (own != null && _same(own, codes)) continue;
    lists[assertion.id] = codes;
  }

  final belgian = {
    for (final entry in _belgianLists.entries)
      entry.value: _variable(source, entry.key, _separators[entry.key]!),
  };
  final profileTypes = _tokenized(
    assertions['PEPPOL-EN16931-P0100']?.test ?? '',
  );

  File(_output).writeAsStringSync(
    _emit(
      added: added,
      syntax: syntax,
      national: national,
      suspended: suspended,
      absent: absent,
      severities: severities,
      lists: lists,
      belgian: belgian,
      profileTypes: profileTypes,
    ),
  );

  // The emitted lists run past the column the formatter wraps at, so what is
  // written and what is committed would differ by a reflow. Formatting here
  // keeps them the same file, which is what lets the build compare them.
  final formatted = Process.runSync('dart', ['format', _output]);
  if (formatted.exitCode != 0) {
    stderr.writeln('dart format failed: ${formatted.stderr}');
    exitCode = 1;
    return;
  }

  stdout.writeln('UBL.BE $ublBeRelease, ${assertions.length} assertions');
  stdout.writeln('  ${added.length} rules beyond EN 16931');
  final counts = <String, int>{};
  for (final assertion in added) {
    counts[_family(assertion.id)] = (counts[_family(assertion.id)] ?? 0) + 1;
  }
  for (final family in counts.keys.toList()..sort()) {
    stdout.writeln('    $family: ${counts[family]}');
  }
  stdout.writeln('  ${syntax.length} rules about the syntax');
  stdout.writeln('  ${national.length} national rules of other countries');
  stdout.writeln('  suspended: ${suspended.join(' ')}');
  stdout.writeln('  absent: ${absent.join(' ')}');
  stdout.writeln('  severity changed: $severities');
  stdout.writeln('  code lists rewritten: ${lists.keys.join(' ')}');
  for (final entry in belgian.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value.length} codes');
  }
  stdout.writeln('${added.length} rules written to $_output');
}

Future<void> _fetch() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_source));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} for $_source');
    }
    final bytes = <int>[];
    await response.forEach(bytes.addAll);
    final digest = sha256.convert(bytes).toString();
    if (digest != _digest) {
      throw StateError(
        'The zip for UBL.BE $ublBeRelease hashes to $digest, where $_digest '
        'was adopted. Read what changed before trusting it.',
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.singleWhere(
      (file) => file.isFile && file.name.endsWith('.sch'),
    );
    Directory('artefacts').createSync(recursive: true);
    File(_artefact).writeAsBytesSync(entry.content);
    stdout.writeln('Fetched $_artefact from UBL.BE $ublBeRelease');
  } finally {
    client.close();
  }
}

/// Prints what the artefact says about the rules starting with [prefix], to
/// read while writing them.
void _dump(XmlDocument document, String prefix) {
  var count = 0;
  for (final assertion in _read(document).values) {
    if (!assertion.id.startsWith(prefix)) continue;
    count++;
    stdout.writeln('${assertion.id} [${assertion.flag}] ${assertion.terms}');
    stdout.writeln('    context: ${_flat(assertion.context)}');
    stdout.writeln('    test: ${_flat(assertion.test)}');
  }
  stdout.writeln('$count rules starting with $prefix');
}

String _flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Every assertion the artefact makes, by identifier, first one kept.
///
/// A parser sees no comment, so a rule the artefact comments out is not read
/// here, which is what it means.
Map<String, _Assertion> _read(XmlDocument document) {
  final found = <String, _Assertion>{};
  for (final rule in document.findAllElements('rule')) {
    final context = rule.getAttribute('context') ?? '';
    for (final assertion in [
      ...rule.findElements('assert'),
      ...rule.findElements('report'),
    ]) {
      final id = assertion.getAttribute('id');
      if (id == null || found.containsKey(id)) continue;
      final test = assertion.getAttribute('test') ?? '';
      found[id] = _Assertion(
        id,
        assertion.getAttribute('flag') ?? rule.getAttribute('flag') ?? '',
        context,
        test,
        _terms(assertion.innerText, '$context $test'),
      );
    }
  }
  return found;
}

/// The identifiers the artefact holds inside comments.
Set<String> _commented(XmlDocument document) => {
  for (final comment in document.descendants.whereType<XmlComment>())
    for (final match in RegExp('id="([^"]+)"').allMatches(comment.value))
      match.group(1)!,
};

/// What a receiver does with an invoice that breaks the rule.
///
/// The artefact flags three levels where the model knows two. A rule flagged
/// information is a remark on an invoice that is otherwise accepted, which is
/// what a warning already is.
String _severity(String flag) => flag == 'fatal' ? 'fatal' : 'warning';

/// The business terms a rule bears on.
///
/// Read out of the message where it names them, and otherwise out of the UBL
/// elements the rule tests.
List<String> _terms(String message, String expression) {
  final found = <String>[];
  final pattern = RegExp(r'\b(?:BT|BG)-\d+(?:-\d+)?\b');
  for (final match in pattern.allMatches(message)) {
    final term = match.group(0)!;
    if (!found.contains(term)) found.add(term);
  }
  if (found.isNotEmpty) return found;
  final element = RegExp(r'cac:(\w+)|cbc:(\w+)');
  for (final match in element.allMatches(expression)) {
    final term = _elementTerms[match.group(1) ?? match.group(2)];
    if (term != null && !found.contains(term)) found.add(term);
  }
  return found;
}

/// The codes a list rule compares against, when it spells them inline.
///
/// BR-CL-01 spells two, one for an invoice and one for a credit note. The
/// model carries one type code whichever root it goes out under, so both are
/// read as one list.
Set<String>? _inlineCodes(String test) {
  final matches = RegExp(r"contains\(\s*'([^']*)'").allMatches(test);
  if (matches.isEmpty) return null;
  return {
    for (final match in matches) ..._codes(match.group(1)!, RegExp(r'\s+')),
  };
}

/// The codes a rule tokenizes inline, as P0100 does its type codes.
Set<String> _tokenized(String test) {
  final match = RegExp(r"tokenize\('([^']*)'").firstMatch(test);
  if (match == null) return const {};
  return _codes(match.group(1)!, RegExp(r'\s+'));
}

/// A list the artefact holds in a Schematron variable.
Set<String> _variable(String source, String name, String separator) {
  final match = RegExp(
    '<let name="$name" value="tokenize\\(\'([^\']*)\'',
  ).firstMatch(source);
  if (match == null) {
    throw StateError('The artefact no longer declares $name.');
  }
  return _codes(match.group(1)!, RegExp(separator));
}

Set<String> _codes(String source, Pattern separator) => source
    .split(separator)
    .map((code) => code.trim())
    .where((code) => code.isNotEmpty)
    .toSet();

bool _same(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// BR-IG-2 sorts before BR-IG-10, which a plain string sort gets backwards.
int _byIdentifier(String a, String b) {
  final family = _family(a).compareTo(_family(b));
  if (family != 0) return family;
  final number = _number(a).compareTo(_number(b));
  if (number != 0) return number;
  return a.compareTo(b);
}

/// An identifier split into the family before its number, and the number.
final RegExp _numbered = RegExp(r'^(.*?)(\d+)(?:-\d+)?$');

int _number(String id) {
  final match = _numbered.firstMatch(id);
  return match == null ? 0 : int.parse(match.group(2)!);
}

String _family(String id) => _numbered.firstMatch(id)?.group(1) ?? id;

String _quote(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

String _emit({
  required List<_Assertion> added,
  required List<String> syntax,
  required List<String> national,
  required List<String> suspended,
  required List<String> absent,
  required Map<String, String> severities,
  required Map<String, Set<String>> lists,
  required Map<String, Set<String>> belgian,
  required Set<String> profileTypes,
}) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by tool/generate_catalogue.dart. Do not edit.')
    ..writeln('//')
    ..writeln('// Read from the UBL.BE rule artefact, release $ublBeRelease.')
    ..writeln('// What is taken from it is which rules exist, how severe each')
    ..writeln('// is, which business terms each bears on, and the codes a rule')
    ..writeln('// compares against.')
    ..writeln()
    ..writeln("import 'package:en16931/en16931.dart';")
    ..writeln()
    ..writeln('/// The UBL.BE release the catalogue was read from.')
    ..writeln("const String ublBeArtefactRelease = '$ublBeRelease';")
    ..writeln()
    ..writeln('/// Every rule UBL.BE states that EN 16931 does not.')
    ..writeln('///')
    ..writeln(
      '/// The Belgian rules, the Peppol rules the artefact carries, and',
    )
    ..writeln('/// the rules of the standard it still holds under a name the')
    ..writeln(
      '/// standard has since dropped. Read from the published artefact,',
    )
    ..writeln(
      '/// so the list is complete by construction rather than by memory.',
    )
    ..writeln('const List<RuleDescriptor> ublBeCatalogue = [');
  for (final assertion in added) {
    final terms = assertion.terms.map((term) => "'$term'").join(', ');
    buffer
      ..writeln('  RuleDescriptor(')
      ..writeln("    id: '${assertion.id}',")
      ..writeln('    family: RuleFamily.profile,')
      ..writeln('    severity: RuleSeverity.${_severity(assertion.flag)},')
      ..writeln('    terms: [$terms],')
      ..writeln('  ),');
  }
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('/// The rules UBL.BE states about how the UBL is written.')
    ..writeln('///')
    ..writeln('/// They bear on the document rather than on the invoice, and')
    ..writeln("/// answering them is the syntax package's business.")
    ..writeln('const Set<String> ublBeSyntaxRules = {');
  for (final id in syntax) {
    buffer.writeln("  '$id',");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The rules Peppol lets another country put on its own sellers.',
    )
    ..writeln('///')
    ..writeln('/// The artefact carries them because it carries Peppol. Each')
    ..writeln('/// bears only on an invoice issued from that country.')
    ..writeln('const Set<String> ublBeNationalRules = {');
  for (final id in national) {
    buffer.writeln("  '$id',");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules of EN 16931 the artefact holds in a comment.')
    ..writeln('///')
    ..writeln('/// UBL.BE took them out on purpose: its conformance statement')
    ..writeln('/// says where Belgian VAT practice parts from the standard.')
    ..writeln('const Set<String> ublBeSuspendedRules = {');
  for (final id in suspended) {
    buffer.writeln("  '$id',");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules of EN 16931 the artefact does not hold at all.')
    ..writeln('///')
    ..writeln('/// Some were deleted from the copy, and some came into the')
    ..writeln('/// standard after the copy was taken.')
    ..writeln('const Set<String> ublBeAbsentRules = {');
  for (final id in absent) {
    buffer.writeln("  '$id',");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules of EN 16931 UBL.BE holds at another severity.')
    ..writeln('const Map<String, RuleSeverity> ublBeSeverities = {');
  for (final entry in severities.entries) {
    buffer.writeln("  '${entry.key}': RuleSeverity.${entry.value},");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The code lists of EN 16931 rules UBL.BE holds differently.')
    ..writeln('///')
    ..writeln('/// The copy keeps the identifier and swaps the list, older in')
    ..writeln('/// places and wider in others, so an invoice can pass one and')
    ..writeln('/// fail the other in either direction.')
    ..writeln('const Map<String, Set<String>> ublBeCodeLists = {');
  for (final id in lists.keys.toList()..sort(_byIdentifier)) {
    final codes = lists[id]!.toList()..sort();
    buffer.writeln("  '$id': {${codes.map(_quote).join(', ')}},");
  }
  buffer.writeln('};');
  for (final entry in belgian.entries) {
    buffer
      ..writeln()
      ..writeln('/// ${_belgianDoc[entry.key]}')
      ..writeln('///')
      ..writeln('/// ${entry.value.length} codes.')
      ..writeln('const Set<String> ${entry.key} = {');
    for (final code in entry.value) {
      buffer.writeln('  ${_quote(code)},');
    }
    buffer.writeln('};');
  }
  final types = profileTypes.toList()..sort();
  buffer
    ..writeln()
    ..writeln('/// The invoice type codes billing process 01 accepts under')
    ..writeln('/// UBL.BE, a shorter list than Peppol holds today.')
    ..writeln('const Set<String> ublBeBillingInvoiceTypes = {')
    ..writeln(types.map(_quote).join(', '))
    ..writeln('};');
  return buffer.toString();
}
