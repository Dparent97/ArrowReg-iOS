export const stopWords = new Set([
  'the','and','or','but','in','on','at','to','for','of','with',
  'by','from','as','is','was','are','were','be','been','have',
  'has','had','do','does','did','will','would','could','should',
  'may','might','must','shall','can','this','that','these','those'
]);

export function tokenize(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

export function removeStopWords(words) {
  return words.filter(w => !stopWords.has(w));
}

export function stem(word) {
  return word.replace(/(ing|ed|s)$/,'');
}

export function processText(text) {
  return removeStopWords(tokenize(text)).map(stem);
}
