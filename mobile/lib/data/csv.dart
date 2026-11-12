String csvField(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp('[",\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String csvTable(List<String> header, Iterable<List<Object?>> rows) => [
  header.join(','),
  for (final r in rows) r.map(csvField).join(','),
].map((line) => '$line\n').join();
