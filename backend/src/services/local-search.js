import { marked } from 'marked';
import fs from 'node:fs';
import path from 'node:path';
import { processText } from '../utils/nlp.js';

class LocalSearchService {
    constructor() {
        this.searchIndex = new Map(); // word -> Map(sectionId -> { tf, documentId, title, sectionNumber })
        this.documents = new Map();
        this.sectionWordCounts = new Map();
        this.totalSections = 0;
        this.initialized = false;
    }

    async initialize() {
        if (this.initialized) return;

        const documentsPath = path.join(process.cwd(), '..', 'data-local');
        
        try {
            await this.loadDocument(path.join(documentsPath, 'ABS-Part-7-Structured.md'), 'abs_part7');
            await this.loadDocument(path.join(documentsPath, 'ECFR-title33.md'), 'cfr33');
            await this.loadDocument(path.join(documentsPath, 'ECFR-title46.md'), 'cfr46');
            
            console.log(`Loaded ${this.documents.size} documents for local search`);
            this.initialized = true;
        } catch (error) {
            console.error('Failed to initialize local search:', error);
            throw error;
        }
    }

    async loadDocument(filePath, documentId) {
        try {
            const content = await fs.promises.readFile(filePath, 'utf8');
            const sections = this.parseMarkdownSections(content, documentId);
            
            this.documents.set(documentId, {
                id: documentId,
                title: this.getDocumentTitle(documentId),
                sections: sections,
                fullContent: content
            });

            // Build search index for this document
            this.indexDocument(documentId, sections);
            
        } catch (error) {
            console.error(`Failed to load document ${documentId}:`, error);
        }
    }

    parseMarkdownSections(content, documentId) {
        const lines = content.split('\n');
        const sections = [];
        let currentSection = null;
        let currentContent = '';

        for (const line of lines) {
            // Detect section headers (# ## ### #### etc.)
            const headerMatch = line.match(/^(#{1,6})\s+(.+)$/);
            
            if (headerMatch) {
                // Save previous section if it exists
                if (currentSection) {
                    sections.push({
                        ...currentSection,
                        content: currentContent.trim(),
                        wordCount: currentContent.trim().split(/\s+/).length
                    });
                }

                // Start new section
                const level = headerMatch[1].length;
                const title = headerMatch[2].trim();
                
                currentSection = {
                    id: `${documentId}_${sections.length}`,
                    title: title,
                    level: level,
                    documentId: documentId,
                    sectionNumber: this.extractSectionNumber(title)
                };
                currentContent = '';
            } else if (currentSection && line.trim()) {
                currentContent += line + '\n';
            }
        }

        // Don't forget the last section
        if (currentSection) {
            sections.push({
                ...currentSection,
                content: currentContent.trim(),
                wordCount: currentContent.trim().split(/\s+/).length
            });
        }

        return sections;
    }

    extractSectionNumber(title) {
        // Extract section numbers like "§ 1.01-1", "Chapter 1", "Part 7", etc.
        const patterns = [
            /§\s*(\d+(?:\.\d+)*(?:-\d+)*)/,  // CFR sections like § 1.01-1
            /Chapter\s+(\d+)/i,              // Chapters
            /Part\s+(\d+)/i,                 // Parts
            /Section\s+(\d+)/i               // Sections
        ];

        for (const pattern of patterns) {
            const match = title.match(pattern);
            if (match) {
                return match[1];
            }
        }

        return null;
    }

    getDocumentTitle(documentId) {
        const titles = {
            'abs_part7': 'ABS Part 7: Survey After Construction',
            'cfr33': '33 CFR: Navigation and Navigable Waters',
            'cfr46': '46 CFR: Shipping'
        };
        return titles[documentId] || documentId;
    }

    indexDocument(documentId, sections) {
        for (const section of sections) {
            const baseText = section.title + ' ' + section.content;
            const tokens = processText(baseText);
            const maritimeTerms = this.extractMaritimeTerms(baseText);
            const allTokens = tokens.concat(maritimeTerms);
            this.sectionWordCounts.set(section.id, allTokens.length);
            const counts = new Map();
            for (const token of allTokens) {
                counts.set(token, (counts.get(token) || 0) + 1);
            }
            for (const [word, count] of counts) {
                if (!this.searchIndex.has(word)) {
                    this.searchIndex.set(word, new Map());
                }
                this.searchIndex.get(word).set(section.id, {
                    documentId: documentId,
                    sectionId: section.id,
                    title: section.title,
                    sectionNumber: section.sectionNumber,
                    tf: count
                });
            }
            this.totalSections += 1;
        }
    }

    extractMaritimeTerms(text) {
        const maritimePatterns = [
            /\b(fire\s+detection|life\s+saving|oil\s+discharge|manning\s+requirements)\b/gi,
            /\b(osv|offshore\s+supply\s+vessel|supply\s+vessel)\b/gi,
            /\b(cfr|code\s+of\s+federal\s+regulations)\b/gi,
            /\b(abs|american\s+bureau\s+of\s+shipping)\b/gi,
            /\b(solas|safety\s+of\s+life\s+at\s+sea)\b/gi,
            /\b(nvic|navigation\s+and\s+vessel\s+inspection\s+circular)\b/gi,
            /\b(machinery\s+space|accommodation|emergency\s+equipment)\b/gi,
            /\b(drydocking|survey|inspection|certification)\b/gi
        ];

        const terms = [];
        for (const pattern of maritimePatterns) {
            const matches = text.matchAll(pattern);
            for (const match of matches) {
                terms.push(match[0].toLowerCase().replace(/\s+/g, '_'));
            }
        }

        return terms;
    }

    async search(query, options = {}) {
        if (!this.initialized) {
            await this.initialize();
        }

        const { maxResults = 10, sources = [] } = options;
        const queryTokens = new Set(processText(query));
        const results = new Map();

        for (const term of queryTokens) {
            if (!this.searchIndex.has(term)) continue;
            const postings = this.searchIndex.get(term);
            const df = postings.size;
            const idf = Math.log((this.totalSections + 1) / (df + 1)) + 1;
            for (const [sectionId, data] of postings) {
                if (sources.length > 0 && !sources.includes(data.documentId)) continue;
                const tf = data.tf / this.sectionWordCounts.get(sectionId);
                const score = tf * idf;
                if (!results.has(sectionId)) {
                    results.set(sectionId, { ...data, score });
                } else {
                    results.get(sectionId).score += score;
                }
            }
        }

        const sortedResults = Array.from(results.values())
            .sort((a, b) => b.score - a.score)
            .slice(0, maxResults);

        return sortedResults.map(result => ({
            ...result,
            content: this.getFullSectionContent(result.documentId, result.sectionId),
            source: this.getSourceInfo(result.documentId),
            confidence: Math.round(Math.min(result.score * 100, 95))
        }));
    }

    getFullSectionContent(documentId, sectionId) {
        const document = this.documents.get(documentId);
        if (!document) return '';

        const section = document.sections.find(s => s.id === sectionId);
        return section ? section.content : '';
    }

    getSourceInfo(documentId) {
        const sourceMap = {
            'abs_part7': { name: 'ABS', type: 'classification', displayName: 'ABS Part 7' },
            'cfr33': { name: 'CFR33', type: 'federal_regulation', displayName: '33 CFR' },
            'cfr46': { name: 'CFR46', type: 'federal_regulation', displayName: '46 CFR' }
        };
        
        return sourceMap[documentId] || { name: documentId, type: 'unknown', displayName: documentId };
    }

    async addDocument(filePath, documentId) {
        await this.loadDocument(filePath, documentId);
        console.log(`Added document ${documentId} to local search index`);
    }

    getAvailableDocuments() {
        return Array.from(this.documents.values()).map(doc => ({
            id: doc.id,
            title: doc.title,
            sectionCount: doc.sections.length
        }));
    }
}

export default LocalSearchService;