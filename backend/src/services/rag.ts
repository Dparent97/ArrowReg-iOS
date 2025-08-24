import fs from 'node:fs';
import path from 'node:path';
import OpenAI from 'openai';

interface Chunk {
  id: string;
  title: string;
  part: string;
  subpart: string;
  section: string;
  text: string;
  bge: number[];
  openai: number[];
  tokens?: string[];
}

class RagService {
  private chunks: Chunk[] = [];
  private docFreq: Map<string, number> = new Map();
  private avgDocLength = 0;
  private initialized = false;
  private openai: OpenAI | null = null;

  private tokenize(text: string): string[] {
    return text
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter(Boolean);
  }

  private buildBM25() {
    const N = this.chunks.length;
    let totalLength = 0;
    for (const chunk of this.chunks) {
      const tokens = this.tokenize(chunk.text);
      chunk.tokens = tokens;
      totalLength += tokens.length;
      const seen = new Set<string>();
      for (const t of tokens) {
        if (!seen.has(t)) {
          this.docFreq.set(t, (this.docFreq.get(t) || 0) + 1);
          seen.add(t);
        }
      }
    }
    this.avgDocLength = totalLength / N;
  }

  async initialize() {
    if (this.initialized) return;
    const dataPath = path.join(process.cwd(), 'src', 'services', 'rag-data', 'cfr-chunks.json');
    const raw = fs.readFileSync(dataPath, 'utf8');
    this.chunks = JSON.parse(raw);
    this.buildBM25();
    const key = process.env.OPENAI_API_KEY;
    this.openai = key ? new OpenAI({ apiKey: key }) : null;
    this.initialized = true;
  }

  private idf(term: string, N: number): number {
    const df = this.docFreq.get(term) || 0;
    return Math.log((N - df + 0.5) / (df + 0.5) + 1);
  }

  private bm25Scores(queryTokens: string[]): Map<string, number> {
    const scores = new Map<string, number>();
    const k1 = 1.5, b = 0.75;
    const N = this.chunks.length;
    for (const chunk of this.chunks) {
      const tf: Record<string, number> = {};
      for (const t of chunk.tokens || []) tf[t] = (tf[t] || 0) + 1;
      let score = 0;
      for (const q of queryTokens) {
        if (!tf[q]) continue;
        const idf = this.idf(q, N);
        const denom = tf[q] + k1 * (1 - b + b * ( (chunk.tokens!.length) / this.avgDocLength ));
        score += idf * (tf[q] * (k1 + 1)) / denom;
      }
      if (score) scores.set(chunk.id, score);
    }
    return scores;
  }

  private cosine(a: number[], b: number[]): number {
    let dot = 0, na = 0, nb = 0;
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (!na || !nb) return 0;
    return dot / (Math.sqrt(na) * Math.sqrt(nb));
  }

  private async embedBGE(text: string): Promise<number[]> {
    try {
      const { pipeline } = await import('@xenova/transformers');
      const extractor = await pipeline('feature-extraction', 'Xenova/bge-base-en');
      const result = await extractor(text, { pooling: 'mean', normalize: true });
      return Array.from(result.data);
    } catch {
      return this.simpleEmbed(text);
    }
  }

  private async embedOpenAI(text: string): Promise<number[]> {
    if (!this.openai) return this.simpleEmbed(text);
    try {
      const resp = await this.openai.embeddings.create({ model: 'text-embedding-3-small', input: text });
      return resp.data[0].embedding;
    } catch {
      return this.simpleEmbed(text);
    }
  }

  private simpleEmbed(text: string): number[] {
    const tokens = this.tokenize(text);
    const vec = [0, 0, 0];
    for (const t of tokens) {
      const h = this.hash(t);
      vec[h % 3] += 1;
    }
    const norm = Math.sqrt(vec.reduce((s, v) => s + v * v, 0));
    return norm ? vec.map(v => v / norm) : vec;
  }

  private hash(str: string): number {
    let h = 0;
    for (let i = 0; i < str.length; i++) h = (h << 5) - h + str.charCodeAt(i);
    return Math.abs(h);
  }

  async search(query: string, topK = 8) {
    await this.initialize();
    const qTokens = this.tokenize(query);
    const bm25 = this.bm25Scores(qTokens);
    const [qBge, qOpen] = await Promise.all([
      this.embedBGE(query),
      this.embedOpenAI(query)
    ]);
    const results = this.chunks.map(ch => {
      const cosBge = this.cosine(qBge, ch.bge);
      const cosOpen = this.cosine(qOpen, ch.openai);
      const cosineScore = (cosBge + cosOpen) / 2;
      const bm25Score = bm25.get(ch.id) || 0;
      const score = 0.5 * cosineScore + 0.5 * (bm25Score || 0);
      return { ch, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, topK)
    .map(r => ({
      title: r.ch.title,
      part: r.ch.part,
      subpart: r.ch.subpart,
      section: r.ch.section,
      text: r.ch.text,
      link: `https://www.ecfr.gov/current/title-${r.ch.title}/part-${r.ch.part}${r.ch.subpart ? `/subpart-${r.ch.subpart}` : ''}/section-${r.ch.section}`,
      score: r.score
    }));
    return results;
  }
}

const service = new RagService();
export default service;
