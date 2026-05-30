String normalizeProductName(String input) {
  var s = input.trim().toUpperCase();

  // Remove common currency tokens
  s = s.replaceAll(RegExp(r'\bR\$\b'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Strip leading item numbers (e.g. "001 BANANA..." or "1) BANANA...")
  s = s.replaceAll(RegExp(r'^\s*\d+\s*[\)\-\.]?\s*'), '');

  // Remove diacritics (pt-BR focused)
  const map = {
    'Á':'A','À':'A','Â':'A','Ã':'A','Ä':'A',
    'É':'E','È':'E','Ê':'E','Ë':'E',
    'Í':'I','Ì':'I','Î':'I','Ï':'I',
    'Ó':'O','Ò':'O','Ô':'O','Õ':'O','Ö':'O',
    'Ú':'U','Ù':'U','Û':'U','Ü':'U',
    'Ç':'C',
    'á':'A','à':'A','â':'A','ã':'A','ä':'A',
    'é':'E','è':'E','ê':'E','ë':'E',
    'í':'I','ì':'I','î':'I','ï':'I',
    'ó':'O','ò':'O','ô':'O','õ':'O','ö':'O',
    'ú':'U','ù':'U','û':'U','ü':'U',
    'ç':'C',
  };

  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(map[ch] ?? ch);
  }

  s = buf.toString();

  // Keep only sane characters
  s = s.replaceAll(RegExp(r'[^A-Z0-9 %\-\.\+/]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}
