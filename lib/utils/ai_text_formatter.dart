String formatAiText(String input) {
  var text = input;

  // Gemini may still return Markdown or LaTeX even when asked for plain text.
  // Convert the most common study-answer notation into readable Flutter text.
  text = text
      .replaceAll(r'\begin{pmatrix}', '[\n')
      .replaceAll(r'\end{pmatrix}', '\n]')
      .replaceAll(r'\begin{bmatrix}', '[\n')
      .replaceAll(r'\end{bmatrix}', '\n]')
      .replaceAll(r'\times', '\u00D7')
      .replaceAll(r'\cdot', '\u00B7')
      .replaceAll(r'\quad', '  ')
      .replaceAll(r'\,', ' ')
      .replaceAll(r'\\', '\n')
      .replaceAll('&', '  ')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll(r'$$', '')
      .replaceAll(r'\[', '')
      .replaceAll(r'\]', '')
      .replaceAll(r'\(', '')
      .replaceAll(r'\)', '');

  text = text.replaceAllMapped(
    RegExp(r'\\text\{([^}]*)\}'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'(?<!\\)\$'), '');
  text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  text = text.replaceAllMapped(
    RegExp(r'^\s*\*([^*]+)\*\s*$', multiLine: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return text.trim();
}
