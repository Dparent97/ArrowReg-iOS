const STOP_WORDS = new Set([
  'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
  'by', 'from', 'as', 'is', 'was', 'are', 'were', 'be', 'been', 'have',
  'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
  'may', 'might', 'must', 'shall', 'can', 'this', 'that', 'these', 'those'
]);

function tokenize(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function stem(word) {
  return word.replace(/(ing|ed|es|s)$/,'');
}

export function preprocess(text) {
  return tokenize(text)
    .map(stem)
    .filter(word => word.length > 2 && !STOP_WORDS.has(word));
}

export { stem, STOP_WORDS };
